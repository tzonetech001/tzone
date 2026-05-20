<?php
// functions.php

function getUnreadNotificationCount($admin_id, $is_admin = false) {
    global $conn;
    
    if (!$admin_id) return 0;
    
    $last_check_sql = "SELECT last_notification_check FROM admins WHERE id = $admin_id";
    $last_check_result = mysqli_query($conn, $last_check_sql);
    $last_check = mysqli_fetch_assoc($last_check_result)['last_notification_check'];
    
    if (!$last_check) return 0;
    
    $count_sql = "SELECT COUNT(*) as count FROM notifications 
                 WHERE status = 'active' 
                 AND created_at > '$last_check'";
    
    // If not admin, filter by visibility
    if (!$is_admin) {
        $count_sql .= " AND (visibility = 'public' OR admin_id = $admin_id)";
    }
    
    $count_result = mysqli_query($conn, $count_sql);
    $count = mysqli_fetch_assoc($count_result)['count'];
    
    return $count;
}

function formatFileSize($bytes) {
    if ($bytes == 0) return '0 Bytes';
    $k = 1024;
    $sizes = ['Bytes', 'KB', 'MB', 'GB'];
    $i = floor(log($bytes) / log($k));
    return round($bytes / pow($k, $i), 2) . ' ' . $sizes[$i];
}
?>