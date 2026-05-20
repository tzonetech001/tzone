-- Additional useful views and procedures

-- Monthly Consumption Summary
CREATE OR REPLACE VIEW `monthly_consumption_summary` AS
SELECT 
    YEAR(consumption_date) as year,
    MONTH(consumption_date) as month,
    MONTHNAME(consumption_date) as month_name,
    COUNT(DISTINCT consumption_date) as days_with_consumption,
    SUM(quantity_used) as total_quantity,
    SUM(quantity_used * unit_price) as total_cost,
    AVG(quantity_used) as avg_daily_usage
FROM daily_consumption dc
JOIN food_items fi ON dc.food_item_id = fi.id
GROUP BY YEAR(consumption_date), MONTH(consumption_date)
ORDER BY year DESC, month DESC;

-- Item Usage Statistics
CREATE OR REPLACE VIEW `item_usage_statistics` AS
SELECT 
    fi.id,
    fi.item_name,
    fi.item_code,
    fi.unit,
    fi.current_quantity,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' THEN ft.quantity ELSE 0 END), 0) as total_used,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'in' THEN ft.quantity ELSE 0 END), 0) as total_added,
    COALESCE(SUM(CASE WHEN ft.purpose = 'consumption' THEN ft.quantity ELSE 0 END), 0) as total_consumption,
    COALESCE(SUM(CASE WHEN ft.purpose = 'waste' THEN ft.quantity ELSE 0 END), 0) as total_waste,
    COALESCE(AVG(CASE WHEN ft.transaction_type = 'in' THEN ft.unit_price END), 0) as avg_purchase_price
FROM food_items fi
LEFT JOIN food_transactions ft ON fi.id = ft.food_item_id
GROUP BY fi.id
ORDER BY total_used DESC;

-- Stock Movement Analysis
CREATE OR REPLACE VIEW `stock_movement_analysis` AS
SELECT 
    fi.item_name,
    fi.item_code,
    fi.unit,
    fi.current_quantity,
    fi.reorder_level,
    DATE_SUB(CURDATE(), INTERVAL 30 DAY) as period_start,
    CURDATE() as period_end,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'in' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) as received_last_30_days,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) as issued_last_30_days,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'in' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity * ft.unit_price END), 0) as value_received,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity * fi.unit_price END), 0) as value_issued
FROM food_items fi
LEFT JOIN food_transactions ft ON fi.id = ft.food_item_id
GROUP BY fi.id;

-- Daily Stock Level Snapshot
CREATE TABLE IF NOT EXISTS `daily_stock_snapshot` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `snapshot_date` DATE NOT NULL,
    `item_id` INT NOT NULL,
    `quantity` DECIMAL(10,2) NOT NULL,
    `unit_price` DECIMAL(10,2) NOT NULL,
    `total_value` DECIMAL(10,2) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_date` (`snapshot_date`),
    INDEX `idx_item` (`item_id`),
    UNIQUE KEY `unique_snapshot` (`snapshot_date`, `item_id`),
    FOREIGN KEY (`item_id`) REFERENCES `food_items`(`id`) ON DELETE CASCADE
);

-- Procedure to create daily snapshot
DELIMITER $$
CREATE PROCEDURE `create_daily_stock_snapshot`()
BEGIN
    INSERT INTO daily_stock_snapshot (snapshot_date, item_id, quantity, unit_price, total_value)
    SELECT 
        CURDATE(),
        fi.id,
        fi.current_quantity,
        fi.unit_price,
        fi.current_quantity * fi.unit_price
    FROM food_items fi
    WHERE fi.status IN ('active', 'out_of_stock')
    ON DUPLICATE KEY UPDATE 
        quantity = VALUES(quantity),
        unit_price = VALUES(unit_price),
        total_value = VALUES(total_value);
END$$
DELIMITER ;

-- Procedure to get item consumption forecast
DELIMITER $$
CREATE PROCEDURE `get_item_consumption_forecast`(
    IN p_item_id INT,
    IN p_days_ahead INT
)
BEGIN
    DECLARE avg_daily_usage DECIMAL(10,2);
    DECLARE current_stock DECIMAL(10,2);
    DECL DAYS_REMAINING INT;
    
    -- Get average daily usage (last 30 days)
    SELECT AVG(dc.quantity_used) INTO avg_daily_usage
    FROM daily_consumption dc
    WHERE dc.food_item_id = p_item_id
    AND dc.consumption_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY);
    
    -- Get current stock
    SELECT current_quantity INTO current_stock
    FROM food_items
    WHERE id = p_item_id;
    
    -- Calculate days remaining
    IF avg_daily_usage > 0 THEN
        SET DAYS_REMAINING = FLOOR(current_stock / avg_daily_usage);
    ELSE
        SET DAYS_REMAINING = 999; -- Infinite if no usage
    END IF;
    
    -- Return forecast
    SELECT 
        p_item_id as item_id,
        current_stock,
        COALESCE(avg_daily_usage, 0) as avg_daily_usage,
        DAYS_REMAINING as days_remaining,
        CASE 
            WHEN DAYS_REMAINING <= 7 THEN 'Critical'
            WHEN DAYS_REMAINING <= 14 THEN 'Warning'
            WHEN DAYS_REMAINING <= 30 THEN 'Monitor'
            ELSE 'Good'
        END as forecast_status,
        DATE_ADD(CURDATE(), INTERVAL DAYS_REMAINING DAY) as estimated_stockout_date;
END$$
DELIMITER ;

-- Procedure to generate reorder report
DELIMITER $$
CREATE PROCEDURE `generate_reorder_report`()
BEGIN
    SELECT 
        fi.id,
        fi.item_code,
        fi.item_name,
        fc.category_name,
        fi.unit,
        fi.current_quantity,
        fi.reorder_level,
        fi.unit_price,
        (fi.current_quantity * fi.unit_price) as current_value,
        (fi.reorder_level * fi.unit_price) as reorder_value,
        fi.supplier,
        fi.storage_location,
        CASE 
            WHEN fi.current_quantity <= 0 THEN 'OUT OF STOCK'
            WHEN fi.current_quantity <= fi.reorder_level THEN 'REORDER NOW'
            WHEN fi.current_quantity <= (fi.reorder_level * 1.5) THEN 'REORDER SOON'
            ELSE 'OK'
        END as reorder_status,
        ROUND((fi.current_quantity / fi.reorder_level) * 100, 2) as stock_percentage
    FROM food_items fi
    LEFT JOIN food_categories fc ON fi.category_id = fc.id
    WHERE fi.status = 'active'
    ORDER BY 
        CASE 
            WHEN fi.current_quantity <= 0 THEN 1
            WHEN fi.current_quantity <= fi.reorder_level THEN 2
            WHEN fi.current_quantity <= (fi.reorder_level * 1.5) THEN 3
            ELSE 4
        END,
        stock_percentage ASC;
END$$
DELIMITER ;

-- Trigger to log stock level changes
DELIMITER $$
CREATE TRIGGER `log_stock_level_change`
AFTER UPDATE ON `food_items`
FOR EACH ROW
BEGIN
    IF OLD.current_quantity != NEW.current_quantity THEN
        INSERT INTO stock_level_logs (
            item_id, 
            old_quantity, 
            new_quantity, 
            change_amount, 
            change_type,
            changed_by,
            change_reason
        ) VALUES (
            NEW.id,
            OLD.current_quantity,
            NEW.current_quantity,
            NEW.current_quantity - OLD.current_quantity,
            CASE 
                WHEN NEW.current_quantity > OLD.current_quantity THEN 'INCREMENT'
                ELSE 'DECREMENT'
            END,
            NEW.updated_by,
            'AUTO_TRACKED'
        );
    END IF;
END$$
DELIMITER ;

-- Create stock_level_logs table if not exists
CREATE TABLE IF NOT EXISTS `stock_level_logs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `item_id` INT NOT NULL,
    `old_quantity` DECIMAL(10,2) NOT NULL,
    `new_quantity` DECIMAL(10,2) NOT NULL,
    `change_amount` DECIMAL(10,2) NOT NULL,
    `change_type` ENUM('INCREMENT', 'DECREMENT') NOT NULL,
    `changed_by` INT DEFAULT NULL,
    `change_reason` VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_item` (`item_id`),
    INDEX `idx_date` (`created_at`),
    FOREIGN KEY (`item_id`) REFERENCES `food_items`(`id`) ON DELETE CASCADE
);
-- Additional Views for Food Store

-- Monthly Stock Movement Summary
CREATE OR REPLACE VIEW `monthly_stock_movement` AS
SELECT 
    YEAR(transaction_date) as year,
    MONTH(transaction_date) as month,
    MONTHNAME(transaction_date) as month_name,
    transaction_type,
    COUNT(*) as transaction_count,
    SUM(quantity) as total_quantity,
    SUM(quantity * unit_price) as total_value,
    COUNT(DISTINCT food_item_id) as unique_items
FROM food_transactions
GROUP BY YEAR(transaction_date), MONTH(transaction_date), transaction_type
ORDER BY year DESC, month DESC, transaction_type;

-- Supplier Performance Analysis
CREATE OR REPLACE VIEW `supplier_performance` AS
SELECT 
    supplier,
    COUNT(DISTINCT food_item_id) as items_supplied,
    COUNT(*) as total_transactions,
    SUM(quantity) as total_quantity,
    SUM(quantity * unit_price) as total_value,
    AVG(unit_price) as avg_unit_price,
    MIN(transaction_date) as first_supply_date,
    MAX(transaction_date) as last_supply_date
FROM food_transactions
WHERE transaction_type = 'in' 
AND supplier IS NOT NULL 
AND supplier != ''
GROUP BY supplier
ORDER BY total_value DESC;

-- Daily Consumption Cost Analysis
CREATE OR REPLACE VIEW `daily_consumption_cost` AS
SELECT 
    consumption_date,
    meal_type,
    served_to,
    SUM(quantity_used) as total_quantity,
    SUM(quantity_used * unit_price) as total_cost,
    AVG(quantity_used * unit_price) as avg_meal_cost,
    SUM(students_count) as total_students,
    SUM(staff_count) as total_staff,
    ROUND(SUM(quantity_used * unit_price) / NULLIF(SUM(students_count + staff_count), 0), 2) as cost_per_person
FROM daily_consumption dc
JOIN food_items fi ON dc.food_item_id = fi.id
GROUP BY consumption_date, meal_type, served_to
ORDER BY consumption_date DESC, 
    FIELD(meal_type, 'breakfast', 'lunch', 'dinner', 'snack');

-- Item Turnover Rate
CREATE OR REPLACE VIEW `item_turnover_rate` AS
SELECT 
    fi.id,
    fi.item_code,
    fi.item_name,
    fi.unit,
    fi.current_quantity,
    fi.reorder_level,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) as monthly_usage,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity * ft.unit_price END), 0) as monthly_usage_value,
    CASE 
        WHEN fi.current_quantity = 0 THEN 0
        WHEN COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) = 0 THEN 999
        ELSE ROUND(fi.current_quantity / (COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) / 30), 1)
    END as days_of_stock,
    CASE 
        WHEN fi.current_quantity = 0 THEN 'Zero Stock'
        WHEN fi.current_quantity <= fi.reorder_level THEN 'Fast Moving'
        WHEN fi.current_quantity <= (fi.reorder_level * 2) THEN 'Medium Moving'
        ELSE 'Slow Moving'
    END as turnover_category
FROM food_items fi
LEFT JOIN food_transactions ft ON fi.id = ft.food_item_id
GROUP BY fi.id
ORDER BY monthly_usage DESC;

-- Storage Location Summary
CREATE OR REPLACE VIEW `storage_location_summary` AS
SELECT 
    storage_location,
    COUNT(*) as item_count,
    SUM(current_quantity) as total_quantity,
    SUM(current_quantity * unit_price) as total_value,
    COUNT(CASE WHEN current_quantity <= 0 THEN 1 END) as out_of_stock_items,
    COUNT(CASE WHEN current_quantity <= reorder_level AND current_quantity > 0 THEN 1 END) as low_stock_items,
    GROUP_CONCAT(DISTINCT category_name ORDER BY category_name SEPARATOR ', ') as categories
FROM current_food_stock
WHERE storage_location IS NOT NULL 
AND storage_location != ''
GROUP BY storage_location
ORDER BY total_value DESC;

-- Weekly Consumption Pattern
CREATE OR REPLACE VIEW `weekly_consumption_pattern` AS
SELECT 
    YEAR(consumption_date) as year,
    WEEK(consumption_date) as week_number,
    MIN(consumption_date) as week_start,
    MAX(consumption_date) as week_end,
    meal_type,
    COUNT(DISTINCT consumption_date) as days_served,
    SUM(quantity_used) as total_quantity,
    SUM(quantity_used * unit_price) as total_cost,
    ROUND(AVG(students_count), 0) as avg_students_per_day,
    ROUND(AVG(staff_count), 0) as avg_staff_per_day,
    ROUND(SUM(quantity_used * unit_price) / NULLIF(SUM(students_count + staff_count), 0), 2) as cost_per_person
FROM daily_consumption dc
JOIN food_items fi ON dc.food_item_id = fi.id
GROUP BY YEAR(consumption_date), WEEK(consumption_date), meal_type
ORDER BY year DESC, week_number DESC, 
    FIELD(meal_type, 'breakfast', 'lunch', 'dinner', 'snack');

-- Food Category Performance
CREATE OR REPLACE VIEW `category_performance` AS
SELECT 
    fc.category_name,
    COUNT(DISTINCT fi.id) as total_items,
    SUM(fi.current_quantity) as total_quantity,
    SUM(fi.current_quantity * fi.unit_price) as total_value,
    COUNT(CASE WHEN fi.current_quantity <= 0 THEN 1 END) as out_of_stock,
    COUNT(CASE WHEN fi.current_quantity <= fi.reorder_level AND fi.current_quantity > 0 THEN 1 END) as low_stock,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) as monthly_usage,
    COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity * ft.unit_price END), 0) as monthly_usage_value,
    ROUND(
        COALESCE(SUM(CASE WHEN ft.transaction_type = 'out' AND ft.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN ft.quantity END), 0) / 
        NULLIF(SUM(fi.current_quantity), 0) * 100, 
        2
    ) as monthly_turnover_rate
FROM food_categories fc
LEFT JOIN food_items fi ON fc.id = fi.category_id
LEFT JOIN food_transactions ft ON fi.id = ft.food_item_id
GROUP BY fc.id
ORDER BY monthly_usage_value DESC;

-- Batch Expiry Tracking
CREATE OR REPLACE VIEW `batch_expiry_tracking` AS
SELECT 
    ft.batch_number,
    fi.item_name,
    fi.item_code,
    ft.expiry_date,
    DATEDIFF(ft.expiry_date, CURDATE()) as days_until_expiry,
    ft.quantity as batch_quantity,
    fi.unit,
    (ft.quantity * ft.unit_price) as batch_value,
    ft.supplier,
    ft.transaction_date as purchase_date,
    CASE 
        WHEN DATEDIFF(ft.expiry_date, CURDATE()) <= 0 THEN 'Expired'
        WHEN DATEDIFF(ft.expiry_date, CURDATE()) <= 7 THEN 'Critical (≤7 days)'
        WHEN DATEDIFF(ft.expiry_date, CURDATE()) <= 30 THEN 'Warning (≤30 days)'
        ELSE 'Normal (>30 days)'
    END as expiry_status,
    ft.notes
FROM food_transactions ft
JOIN food_items fi ON ft.food_item_id = fi.id
WHERE ft.expiry_date IS NOT NULL
AND ft.transaction_type = 'in'
AND EXISTS (
    SELECT 1 FROM food_items fi2 
    WHERE fi2.id = ft.food_item_id 
    AND fi2.current_quantity > 0
)
ORDER BY expiry_date ASC, expiry_status;

-- Waste Analysis Report
CREATE OR REPLACE VIEW `waste_analysis_report` AS
SELECT 
    YEAR(waste_date) as year,
    MONTH(waste_date) as month,
    MONTHNAME(waste_date) as month_name,
    reason,
    COUNT(*) as incident_count,
    SUM(quantity) as total_quantity,
    SUM(estimated_value) as total_value,
    GROUP_CONCAT(DISTINCT responsible_person ORDER BY responsible_person SEPARATOR ', ') as responsible_persons,
    AVG(estimated_value) as avg_incident_value
FROM food_waste_damage
GROUP BY YEAR(waste_date), MONTH(waste_date), reason
ORDER BY year DESC, month DESC, total_value DESC;

-- Comprehensive Dashboard Summary
CREATE OR REPLACE VIEW `food_store_dashboard` AS
SELECT 
    -- Inventory Summary
    (SELECT COUNT(*) FROM food_items WHERE status = 'active') as total_active_items,
    (SELECT SUM(current_quantity) FROM food_items WHERE status = 'active') as total_quantity,
    (SELECT SUM(current_quantity * unit_price) FROM food_items WHERE status = 'active') as total_inventory_value,
    
    -- Low Stock Summary
    (SELECT COUNT(*) FROM current_food_stock WHERE stock_status = 'Low Stock') as low_stock_items,
    (SELECT COUNT(*) FROM current_food_stock WHERE stock_status = 'Out of Stock') as out_of_stock_items,
    
    -- Today's Activity
    (SELECT COUNT(*) FROM food_transactions WHERE transaction_date = CURDATE()) as today_transactions,
    (SELECT SUM(quantity * unit_price) FROM food_transactions WHERE transaction_date = CURDATE() AND transaction_type = 'in') as today_purchases,
    (SELECT SUM(quantity_used * unit_price) FROM daily_consumption dc JOIN food_items fi ON dc.food_item_id = fi.id WHERE consumption_date = CURDATE()) as today_consumption_cost,
    
    -- Monthly Activity
    (SELECT COUNT(*) FROM food_transactions WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) as monthly_transactions,
    (SELECT SUM(quantity * unit_price) FROM food_transactions WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) AND transaction_type = 'in') as monthly_purchases,
    (SELECT SUM(quantity_used * unit_price) FROM daily_consumption dc JOIN food_items fi ON dc.food_item_id = fi.id WHERE consumption_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) as monthly_consumption_cost,
    
    -- Alert Summary
    (SELECT COUNT(*) FROM stock_alerts WHERE status = 'active') as active_alerts,
    (SELECT COUNT(*) FROM stock_alerts WHERE alert_type = 'expiry' AND status = 'active') as expiry_alerts,
    
    -- Waste Summary
    (SELECT SUM(quantity) FROM food_waste_damage WHERE waste_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) as monthly_waste_quantity,
    (SELECT SUM(estimated_value) FROM food_waste_damage WHERE waste_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)) as monthly_waste_value;

-- Stock Value by Category (for Pie Chart)
CREATE OR REPLACE VIEW `stock_value_by_category` AS
SELECT 
    COALESCE(fc.category_name, 'Uncategorized') as category,
    SUM(fi.current_quantity * fi.unit_price) as total_value,
    ROUND((SUM(fi.current_quantity * fi.unit_price) / NULLIF((SELECT SUM(current_quantity * unit_price) FROM food_items WHERE status = 'active'), 0) * 100), 2) as percentage
FROM food_items fi
LEFT JOIN food_categories fc ON fi.category_id = fc.id
WHERE fi.status = 'active'
GROUP BY fc.category_name
ORDER BY total_value DESC;

-- Monthly Consumption by Category
CREATE OR REPLACE VIEW `monthly_consumption_by_category` AS
SELECT 
    YEAR(dc.consumption_date) as year,
    MONTH(dc.consumption_date) as month,
    MONTHNAME(dc.consumption_date) as month_name,
    COALESCE(fc.category_name, 'Uncategorized') as category,
    SUM(dc.quantity_used) as total_quantity,
    SUM(dc.quantity_used * fi.unit_price) as total_cost,
    COUNT(DISTINCT dc.consumption_date) as days_with_consumption,
    ROUND(AVG(dc.quantity_used), 2) as avg_daily_quantity,
    ROUND(SUM(dc.quantity_used * fi.unit_price) / NULLIF(SUM(dc.quantity_used), 0), 2) as avg_unit_cost
FROM daily_consumption dc
JOIN food_items fi ON dc.food_item_id = fi.id
LEFT JOIN food_categories fc ON fi.category_id = fc.id
GROUP BY YEAR(dc.consumption_date), MONTH(dc.consumption_date), fc.category_name
ORDER BY year DESC, month DESC, total_cost DESC;