<?php
// Food Store Common Functions

/**
 * Check if user has Food Store access
 */
function hasFoodStoreAccess($admin_id, $conn) {
    $role_check_sql = "SELECT ar.role_name 
                      FROM admin_role_assignments ara
                      JOIN admin_roles ar ON ara.role_id = ar.id
                      WHERE ara.admin_id = ? 
                      AND ar.role_name IN ('Food Store', 'Head Master')";
    $stmt = $conn->prepare($role_check_sql);
    $stmt->bind_param("i", $admin_id);
    $stmt->execute();
    $result = $stmt->get_result();
    return $result->num_rows > 0;
}

/**
 * Get food item details
 */
function getFoodItem($item_id, $conn) {
    $sql = "SELECT * FROM food_items WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $item_id);
    $stmt->execute();
    $result = $stmt->get_result();
    return $result->fetch_assoc();
}

/**
 * Get all food categories
 */
function getFoodCategories($conn, $active_only = true) {
    $sql = "SELECT * FROM food_categories";
    if ($active_only) {
        $sql .= " WHERE status = 'active'";
    }
    $sql .= " ORDER BY category_name";
    
    $result = $conn->query($sql);
    $categories = [];
    while ($cat = $result->fetch_assoc()) {
        $categories[] = $cat;
    }
    return $categories;
}

/**
 * Generate next item code
 */
function generateItemCode($conn, $prefix = 'FD') {
    $year_month = date('ym');
    $sql = "SELECT MAX(item_code) as max_code 
            FROM food_items 
            WHERE item_code LIKE '{$prefix}{$year_month}%'";
    $result = $conn->query($sql);
    $row = $result->fetch_assoc();
    
    if ($row['max_code']) {
        $last_num = intval(substr($row['max_code'], -3));
        $next_num = str_pad($last_num + 1, 3, '0', STR_PAD_LEFT);
    } else {
        $next_num = '001';
    }
    
    return $prefix . $year_month . $next_num;
}

/**
 * Calculate item statistics
 */
function getItemStatistics($item_id, $conn) {
    $stats = [
        'total_in' => 0,
        'total_out' => 0,
        'total_waste' => 0,
        'avg_monthly_usage' => 0,
        'days_of_stock' => 0
    ];
    
    // Get transaction totals
    $sql = "SELECT 
        SUM(CASE WHEN transaction_type = 'in' THEN quantity ELSE 0 END) as total_in,
        SUM(CASE WHEN transaction_type = 'out' THEN quantity ELSE 0 END) as total_out,
        SUM(CASE WHEN transaction_type = 'waste' THEN quantity ELSE 0 END) as total_waste
    FROM food_transactions 
    WHERE food_item_id = ?";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $item_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $tx_stats = $result->fetch_assoc();
    
    if ($tx_stats) {
        $stats['total_in'] = $tx_stats['total_in'] ?? 0;
        $stats['total_out'] = $tx_stats['total_out'] ?? 0;
        $stats['total_waste'] = $tx_stats['total_waste'] ?? 0;
    }
    
    // Get current stock
    $stock_sql = "SELECT current_quantity FROM food_items WHERE id = ?";
    $stock_stmt = $conn->prepare($stock_sql);
    $stock_stmt->bind_param("i", $item_id);
    $stock_stmt->execute();
    $stock_result = $stock_stmt->get_result();
    $stock = $stock_result->fetch_assoc();
    
    // Calculate average monthly usage (last 3 months)
    $usage_sql = "SELECT AVG(quantity) as avg_usage 
                 FROM food_transactions 
                 WHERE food_item_id = ? 
                 AND transaction_type = 'out' 
                 AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)";
    
    $usage_stmt = $conn->prepare($usage_sql);
    $usage_stmt->bind_param("i", $item_id);
    $usage_stmt->execute();
    $usage_result = $usage_stmt->get_result();
    $usage = $usage_result->fetch_assoc();
    
    $stats['avg_monthly_usage'] = $usage['avg_usage'] ?? 0;
    
    // Calculate days of stock remaining
    if ($stats['avg_monthly_usage'] > 0) {
        $stats['days_of_stock'] = ($stock['current_quantity'] / ($stats['avg_monthly_usage'] / 30));
    }
    
    return $stats;
}

/**
 * Check stock availability
 */
function checkStockAvailability($item_id, $quantity, $conn) {
    $sql = "SELECT current_quantity, unit FROM food_items WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $item_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $item = $result->fetch_assoc();
    
    if (!$item) {
        return ['available' => false, 'message' => 'Item not found'];
    }
    
    if ($item['current_quantity'] >= $quantity) {
        return ['available' => true, 'unit' => $item['unit']];
    } else {
        return [
            'available' => false, 
            'message' => "Insufficient stock. Available: {$item['current_quantity']} {$item['unit']}"
        ];
    }
}

/**
 * Generate consumption report
 */
function generateConsumptionReport($start_date, $end_date, $conn) {
    $sql = "SELECT 
        dc.consumption_date,
        dc.meal_type,
        fi.item_name,
        fi.category_name,
        dc.quantity_used,
        dc.unit,
        dc.served_to,
        dc.students_count,
        dc.staff_count,
        (dc.quantity_used * fi.unit_price) as cost,
        dc.prepared_by,
        a.first_name as recorded_by_first,
        a.last_name as recorded_by_last,
        dc.notes
    FROM daily_consumption dc
    JOIN food_items fi ON dc.food_item_id = fi.id
    JOIN admins a ON dc.recorded_by = a.id
    WHERE dc.consumption_date BETWEEN ? AND ?
    ORDER BY dc.consumption_date DESC, dc.meal_type, fi.item_name";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $report = [];
    $totals = [
        'total_quantity' => 0,
        'total_cost' => 0,
        'total_students' => 0,
        'total_staff' => 0,
        'days_count' => 0
    ];
    
    $unique_dates = [];
    
    while ($row = $result->fetch_assoc()) {
        $report[] = $row;
        
        $totals['total_quantity'] += $row['quantity_used'];
        $totals['total_cost'] += $row['cost'];
        $totals['total_students'] += $row['students_count'];
        $totals['total_staff'] += $row['staff_count'];
        
        if (!in_array($row['consumption_date'], $unique_dates)) {
            $unique_dates[] = $row['consumption_date'];
            $totals['days_count']++;
        }
    }
    
    return [
        'data' => $report,
        'totals' => $totals,
        'period' => [
            'start' => $start_date,
            'end' => $end_date,
            'days' => $totals['days_count']
        ]
    ];
}

/**
 * Generate low stock alert
 */
function generateLowStockAlerts($conn, $threshold_multiplier = 1.5) {
    $sql = "SELECT 
        fi.id,
        fi.item_code,
        fi.item_name,
        fi.current_quantity,
        fi.unit,
        fi.reorder_level,
        fi.unit_price,
        (fi.current_quantity * fi.unit_price) as current_value,
        CASE 
            WHEN fi.current_quantity <= 0 THEN 'Out of Stock'
            WHEN fi.current_quantity <= fi.reorder_level THEN 'Critical'
            WHEN fi.current_quantity <= (fi.reorder_level * ?) THEN 'Warning'
            ELSE 'Normal'
        END as alert_level
    FROM food_items fi
    WHERE fi.status = 'active'
    HAVING alert_level IN ('Out of Stock', 'Critical', 'Warning')
    ORDER BY 
        CASE alert_level
            WHEN 'Out of Stock' THEN 1
            WHEN 'Critical' THEN 2
            WHEN 'Warning' THEN 3
        END,
        fi.current_quantity / fi.reorder_level";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("d", $threshold_multiplier);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $alerts = [];
    while ($row = $result->fetch_assoc()) {
        $alerts[] = $row;
    }
    
    return $alerts;
}

/**
 * Get expiry alerts
 */
function getExpiryAlerts($conn, $days_ahead = 30) {
    $sql = "SELECT 
        ft.food_item_id,
        fi.item_code,
        fi.item_name,
        ft.batch_number,
        ft.expiry_date,
        DATEDIFF(ft.expiry_date, CURDATE()) as days_until_expiry,
        ft.quantity as batch_quantity,
        fi.unit,
        (ft.quantity * ft.unit_price) as batch_value
    FROM food_transactions ft
    JOIN food_items fi ON ft.food_item_id = fi.id
    WHERE ft.expiry_date IS NOT NULL
    AND ft.expiry_date >= CURDATE()
    AND ft.expiry_date <= DATE_ADD(CURDATE(), INTERVAL ? DAY)
    AND ft.transaction_type = 'in'
    AND EXISTS (
        SELECT 1 FROM food_items fi2 
        WHERE fi2.id = ft.food_item_id 
        AND fi2.current_quantity > 0
    )
    ORDER BY ft.expiry_date ASC";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $days_ahead);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $expiries = [];
    while ($row = $result->fetch_assoc()) {
        $expiries[] = $row;
    }
    
    return $expiries;
}

/**
 * Generate purchase order suggestions
 */
function generatePurchaseOrderSuggestions($conn) {
    // Get items below reorder level
    $sql = "SELECT 
        fi.id,
        fi.item_code,
        fi.item_name,
        fi.unit,
        fi.current_quantity,
        fi.reorder_level,
        fi.unit_price,
        (fi.reorder_level - fi.current_quantity) as quantity_needed,
        ((fi.reorder_level - fi.current_quantity) * fi.unit_price) as estimated_cost,
        fi.supplier,
        fi.storage_location,
        AVG(CASE WHEN ft.transaction_type = 'in' THEN ft.unit_price END) as avg_purchase_price,
        MAX(CASE WHEN ft.transaction_type = 'in' THEN ft.transaction_date END) as last_purchase_date
    FROM food_items fi
    LEFT JOIN food_transactions ft ON fi.id = ft.food_item_id
    WHERE fi.status = 'active'
    AND fi.current_quantity <= (fi.reorder_level * 1.5)
    GROUP BY fi.id
    HAVING quantity_needed > 0
    ORDER BY (fi.current_quantity / fi.reorder_level) ASC";
    
    $result = $conn->query($sql);
    
    $suggestions = [];
    $total_cost = 0;
    
    while ($row = $result->fetch_assoc()) {
        $suggestions[] = $row;
        $total_cost += $row['estimated_cost'];
    }
    
    return [
        'suggestions' => $suggestions,
        'total_cost' => $total_cost,
        'item_count' => count($suggestions)
    ];
}

/**
 * Format currency
 */
function formatCurrency($amount) {
    return 'TZS ' . number_format($amount, 2);
}

/**
 * Get stock status badge HTML
 */
function getStockStatusBadge($current_quantity, $reorder_level) {
    if ($current_quantity <= 0) {
        return '<span class="badge bg-danger">Out of Stock</span>';
    } elseif ($current_quantity <= $reorder_level) {
        return '<span class="badge bg-warning">Low Stock</span>';
    } elseif ($current_quantity <= ($reorder_level * 2)) {
        return '<span class="badge bg-info">Moderate</span>';
    } else {
        return '<span class="badge bg-success">Good</span>';
    }
}

/**
 * Get transaction type badge HTML
 */
function getTransactionTypeBadge($type) {
    $badges = [
        'in' => ['class' => 'success', 'text' => 'IN'],
        'out' => ['class' => 'warning', 'text' => 'OUT'],
        'waste' => ['class' => 'danger', 'text' => 'WASTE'],
        'adjustment' => ['class' => 'info', 'text' => 'ADJUST']
    ];
    
    $config = $badges[$type] ?? ['class' => 'secondary', 'text' => strtoupper($type)];
    return '<span class="badge bg-' . $config['class'] . '">' . $config['text'] . '</span>';
}

/**
 * Validate and sanitize food item data
 */
function validateFoodItemData($data) {
    $errors = [];
    
    // Validate item name
    if (empty(trim($data['item_name']))) {
        $errors[] = 'Item name is required';
    } elseif (strlen(trim($data['item_name'])) > 200) {
        $errors[] = 'Item name must be less than 200 characters';
    }
    
    // Validate unit
    $valid_units = ['kg', 'g', 'liter', 'ml', 'piece', 'packet', 'bag', 'box', 'carton'];
    if (!in_array($data['unit'], $valid_units)) {
        $errors[] = 'Invalid unit selected';
    }
    
    // Validate quantities
    if ($data['reorder_level'] < 0) {
        $errors[] = 'Reorder level cannot be negative';
    }
    
    if ($data['unit_price'] < 0) {
        $errors[] = 'Unit price cannot be negative';
    }
    
    // Validate expiry days
    if (!empty($data['expiry_days']) && $data['expiry_days'] < 0) {
        $errors[] = 'Expiry days cannot be negative';
    }
    
    return $errors;
}
?>