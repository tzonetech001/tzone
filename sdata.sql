-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Apr 03, 2026 at 08:12 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `tzone_high`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `assign_student_to_dormitory` (IN `p_student_id` INT, IN `p_dormitory_id` INT, IN `p_room_id` INT, IN `p_bed_number` VARCHAR(10), IN `p_assigned_by` INT, IN `p_notes` TEXT)   BEGIN
    DECLARE v_student_name VARCHAR(201);
    
    START TRANSACTION;
    
    -- Get student name for error messages
    SELECT CONCAT(first_name, ' ', last_name) INTO v_student_name
    FROM students WHERE id = p_student_id;
    
    -- Insert the assignment (triggers will handle validation and occupancy updates)
    INSERT INTO student_dormitory (student_id, dormitory_id, room_id, bed_number, assigned_by, status, notes)
    VALUES (p_student_id, p_dormitory_id, p_room_id, p_bed_number, p_assigned_by, 'Active', p_notes);
    
    COMMIT;
    
    SELECT 'SUCCESS' as status, CONCAT('Student ', v_student_name, ' assigned to dormitory successfully!') as message;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_available_rooms` (IN `p_dormitory_id` INT)   BEGIN
    SELECT 
        dr.id,
        dr.room_number,
        dr.room_label,
        dr.capacity,
        dr.current_occupancy,
        (dr.capacity - dr.current_occupancy) as available_beds,
        dr.status,
        d.dorm_name,
        d.dorm_type
    FROM dormitory_rooms dr
    JOIN dormitories d ON dr.dormitory_id = d.id
    WHERE dr.dormitory_id = p_dormitory_id
    AND dr.status = 'Available'
    AND dr.current_occupancy < dr.capacity
    ORDER BY dr.room_number;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `graduate_form_six_students` (IN `p_academic_year` VARCHAR(9), IN `p_graduation_date` DATE, IN `p_admin_id` INT, IN `p_student_ids` TEXT)   BEGIN
    DECLARE v_student_id INT;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE cur_students CURSOR FOR 
        SELECT id FROM students 
        WHERE FIND_IN_SET(id, p_student_ids) > 0 
        AND class = 'Form Six' 
        AND is_leaver = 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    
    OPEN cur_students;
    
    graduation_loop:LOOP
        FETCH cur_students INTO v_student_id;
        IF v_done THEN
            LEAVE graduation_loop;
        END IF;
        
        UPDATE students 
        SET is_leaver = 1,
            graduation_status = 'Graduated',
            graduation_year = YEAR(p_graduation_date),
            year_left = YEAR(p_graduation_date),
            status = 0,
            updated_by_admin = p_admin_id
        WHERE id = v_student_id;
        
        INSERT INTO student_graduation_history (
            student_id, from_class, to_class, academic_year,
            graduation_type, graduation_date, recorded_by
        ) VALUES (
            v_student_id, 'Form Six', 'Graduated', p_academic_year,
            'Graduation', p_graduation_date, p_admin_id
        );
        
    END LOOP;
    
    CLOSE cur_students;
    
    SELECT CONCAT('Graduated ', ROW_COUNT(), ' Form Six students') as result;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `promote_form_five_to_six` (IN `p_academic_year` VARCHAR(9), IN `p_promotion_date` DATE, IN `p_admin_id` INT, IN `p_student_ids` TEXT)   BEGIN
    DECLARE v_student_id INT;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE cur_students CURSOR FOR 
        SELECT id FROM students 
        WHERE FIND_IN_SET(id, p_student_ids) > 0 
        AND class = 'Form Five' 
        AND is_leaver = 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    
    OPEN cur_students;
    
    promotion_loop: LOOP
        FETCH cur_students INTO v_student_id;
        IF v_done THEN
            LEAVE promotion_loop;
        END IF;
        
        UPDATE students 
        SET class = 'Form Six',
            previous_class = 'Form Five',
            class_changed_at = CURRENT_TIMESTAMP,
            promotion_status = 'Promoted to Form Six',
            updated_by_admin = p_admin_id
        WHERE id = v_student_id;
        
        INSERT INTO student_graduation_history (
            student_id, from_class, to_class, academic_year,
            graduation_type, graduation_date, recorded_by
        ) VALUES (
            v_student_id, 'Form Five', 'Form Six', p_academic_year,
            'Promotion', p_promotion_date, p_admin_id
        );
        
    END LOOP;
    
    CLOSE cur_students;
    
    SELECT CONCAT('Promoted ', ROW_COUNT(), ' students from Form Five to Form Six') as result;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `remove_dormitory_assignment` (IN `p_assignment_id` INT, IN `p_notes` TEXT)   BEGIN
    DECLARE v_student_name VARCHAR(201);
    DECLARE v_student_id INT;
    
    START TRANSACTION;
    
    -- Get student info
    SELECT s.id, CONCAT(s.first_name, ' ', s.last_name) INTO v_student_id, v_student_name
    FROM student_dormitory sd
    JOIN students s ON sd.student_id = s.id
    WHERE sd.id = p_assignment_id;
    
    IF v_student_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Assignment not found!';
    END IF;
    
    -- Update assignment status (triggers will handle occupancy)
    UPDATE student_dormitory 
    SET status = 'Left', 
        notes = CONCAT(COALESCE(notes, ''), ' | Removed: ', p_notes),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_assignment_id;
    
    COMMIT;
    
    SELECT 'SUCCESS' as status, CONCAT('Assignment for ', v_student_name, ' removed successfully!') as message;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `update_student_dormitory` (IN `p_assignment_id` INT, IN `p_new_dormitory_id` INT, IN `p_new_room_id` INT, IN `p_new_bed_number` VARCHAR(10), IN `p_updated_by` INT, IN `p_notes` TEXT)   BEGIN
    DECLARE v_old_room_id INT;
    DECLARE v_old_dormitory_id INT;
    DECLARE v_student_id INT;
    DECLARE v_student_name VARCHAR(201);
    
    START TRANSACTION;
    
    -- Get current assignment details
    SELECT room_id, dormitory_id, student_id INTO v_old_room_id, v_old_dormitory_id, v_student_id
    FROM student_dormitory 
    WHERE id = p_assignment_id AND status = 'Active';
    
    IF v_old_room_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Active assignment not found!';
    END IF;
    
    -- Get student name
    SELECT CONCAT(first_name, ' ', last_name) INTO v_student_name
    FROM students WHERE id = v_student_id;
    
    -- Check new room capacity
    IF EXISTS (
        SELECT 1 FROM dormitory_rooms 
        WHERE id = p_new_room_id 
        AND current_occupancy >= capacity
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New room is already at full capacity!';
    END IF;
    
    -- Update assignment (triggers will handle room occupancy changes)
    UPDATE student_dormitory 
    SET dormitory_id = p_new_dormitory_id,
        room_id = p_new_room_id,
        bed_number = p_new_bed_number,
        notes = CONCAT(COALESCE(notes, ''), ' | Changed: ', p_notes),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_assignment_id;
    
    COMMIT;
    
    SELECT 'SUCCESS' as status, CONCAT('Assignment for ', v_student_name, ' updated successfully!') as message;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `admins`
--

CREATE TABLE `admins` (
  `id` int(11) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `last_name` varchar(50) NOT NULL,
  `sex` enum('Male','Female') NOT NULL,
  `email` varchar(100) NOT NULL,
  `check_number` varchar(50) DEFAULT NULL,
  `phone_number` varchar(20) NOT NULL,
  `nida` varchar(20) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `reset_otp` varchar(6) DEFAULT NULL,
  `reset_otp_expiry` datetime DEFAULT NULL,
  `last_password_change` datetime DEFAULT NULL,
  `profile_image` varchar(255) DEFAULT NULL,
  `status` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `last_notification_check` timestamp NULL DEFAULT NULL,
  `address` text DEFAULT NULL,
  `updated_by_admin` int(11) DEFAULT NULL,
  `failed_login_attempts` int(11) DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `last_login_attempt` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admins`
--

INSERT INTO `admins` (`id`, `first_name`, `middle_name`, `last_name`, `sex`, `email`, `check_number`, `phone_number`, `nida`, `password`, `reset_otp`, `reset_otp_expiry`, `last_password_change`, `profile_image`, `status`, `created_at`, `updated_at`, `last_notification_check`, `address`, `updated_by_admin`, `failed_login_attempts`, `locked_until`, `last_login_attempt`) VALUES
(12, 'muyovozi', '', 'muyovozi', 'Male', 'admin@muyovozi.ac.tz', '', '255714343162', NULL, '$2y$10$4i9hIukEfe2nUj2dOsr9segLg1GlzZn1I3TNFgn3a0LGDNoHNPvNu', NULL, NULL, NULL, 'admin_12_1768193337.jpeg', 1, '2026-01-06 04:26:58', '2026-03-14 13:42:08', '2026-01-23 14:28:24', '', NULL, 0, NULL, '2026-03-14 16:42:08'),
(13, 'ashura', 'tophic', 'mussa', 'Female', 'ashuu@gmail.com', '6578887654', '255790909090', '67543234569769767779', '$2y$10$e5BNkjFn7DkSBmkzFJn9SO5gaDsb2G2rZUWwTmvSuyMIajUCfknM2', NULL, NULL, NULL, 'admin_13_1773396332.jpg', 1, '2026-01-07 11:53:03', '2026-03-13 19:59:08', '2026-01-23 14:28:24', '', NULL, 0, NULL, '2026-03-13 22:59:08'),
(14, 'samson', 'tophic', 'smith', 'Male', 'sam@gmail.com', '', '255790909087', '67549874567890987658', '$2y$10$sA7LcE/vF6AO4gB.mZ7kzu5ZB6Xlc8L9s9Qb0zItuhE9KO11UFpTq', NULL, NULL, NULL, '', 1, '2026-01-09 11:44:30', '2026-04-02 07:26:12', '2026-01-23 14:28:24', '', NULL, 0, NULL, '2026-04-02 10:26:12'),
(15, 'aujenia', 'tophic', 'leo', 'Female', 'jen@gmail.com', '', '255714343162', NULL, '$2y$10$lPtgR8Q4VoNdTalk16tfs.5GsoOT4RJgEZFELQr3Uabf/ILdJAo1y', NULL, NULL, NULL, NULL, 1, '2026-01-21 15:05:50', '2026-03-11 15:49:59', '2026-01-23 14:28:24', NULL, NULL, 0, NULL, NULL),
(17, 'muyovozi', '', 'muyovozi', 'Male', 'muyovozi@gmail.com', '', '255766666666', '', '$2y$10$dvjQN799SCRkRaw0oz9gnOqMFKRqlc.yUOzehQTh42goE7Si6pz9.', NULL, NULL, NULL, 'admin_17_1773497651.jpg', 1, '2026-02-06 16:16:46', '2026-03-14 14:14:11', NULL, '', NULL, 0, NULL, '2026-03-14 16:46:08'),
(26, 'Franc', 'leonard', 'peter', 'Female', 'franc@gmail.com', '', '255763243765', '', '$2y$10$MSfDiwF6ZreWiT1hN0JZi.Dv3Zfc/XwB9jnrbX.gKr2HriZezD5K.', NULL, NULL, NULL, 'admin_26_1773393622.jpg', 1, '2026-03-08 05:37:43', '2026-03-14 12:57:26', NULL, '', NULL, 0, NULL, '2026-03-14 15:57:26'),
(28, 'kafunsi', 'juma', 'kafunsi', 'Male', 'kafunsi@gmail.com', '', '255712837307', NULL, '$2y$10$VlzGpDTLjMB1c/8wxOTwJ.PIdkzwpDqFEdSB8wWcU0Vzw2BxFIB1W', NULL, NULL, NULL, NULL, 1, '2026-03-11 17:33:32', '2026-04-01 06:10:39', NULL, NULL, NULL, 0, NULL, '2026-04-01 09:10:39'),
(29, 'bamfu', 'leonard', 'bamfu', 'Male', 'bbamfu@gmail.com', '', '255823792374', NULL, '$2y$10$7bHZxlhMsRuYV9GTzAkFze9p9QFb085.Na2DWTTgkvgFsA0jT6Zkm', NULL, NULL, NULL, NULL, 1, '2026-03-13 12:11:33', '2026-03-14 14:16:59', NULL, NULL, NULL, 0, NULL, '2026-03-14 17:16:59'),
(31, 'Tzone', 'IT', 'TZ', 'Male', 'tz@gmail.com', NULL, '255714343162', '', '$2y$10$4vmF017Z93adwWHJYIWzZOP4ARAf39V7sSlxZZBV0usElEgR8TrtK', NULL, NULL, NULL, 'admin_31_1773490494.jpg', 1, '2026-03-13 12:55:59', '2026-03-14 17:56:00', NULL, '', NULL, 0, NULL, '2026-03-14 20:56:00'),
(32, 'tz', 'tz', 'tz', 'Male', 'tzone@gmail.com', '', '255783626760', NULL, '$2y$10$WbeCJLk5D6T3xS6eeb6hWeYc0lxQ1iKZT7QJeXdSQEXpPw5/cKTI6', NULL, NULL, NULL, NULL, 1, '2026-03-13 13:10:00', '2026-04-03 03:57:31', NULL, NULL, NULL, 0, NULL, '2026-04-03 06:57:31'),
(34, 'Halima', 'leonard', 'peter', 'Female', 'fdiva5045@gmail.com', '', '255672389209', NULL, '$2y$10$4pa7e4B3hU1ofNKDsFg50OwZeXYVz0rbUbzzaoC1KwDMiSoPccOva', NULL, NULL, NULL, NULL, 1, '2026-03-14 15:26:23', '2026-03-14 17:57:08', NULL, NULL, NULL, 0, NULL, NULL),
(35, 'agness', 'wiston', 'taze', 'Female', 'agness@gmail.com', '', '255755914218', NULL, '$2y$10$46jLXl0Kbxyr50R5PdW3sen196INZuvSIXzCQDoGADqG/jS03adHS', NULL, NULL, NULL, 'admin_35_1774606773.jpg', 1, '2026-03-27 10:17:22', '2026-04-02 14:30:51', NULL, '', NULL, 0, NULL, '2026-04-02 17:30:51'),
(36, 'herjmpew', 'upo', 'mzima', 'Female', 'ee@gmail.com', '', '255694372484', NULL, '$2y$10$nIxAd278uIJxsZrMmGt4NulqYKRTXs8.OjCuPkJk7A/BePsDi6sRm', NULL, NULL, NULL, NULL, 1, '2026-04-02 10:36:08', '2026-04-02 10:36:08', NULL, NULL, NULL, 0, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `admin_login_attempts`
--

CREATE TABLE `admin_login_attempts` (
  `id` int(11) NOT NULL,
  `identifier` varchar(255) NOT NULL,
  `success` tinyint(1) DEFAULT 0,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `attempt_time` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin_login_attempts`
--

INSERT INTO `admin_login_attempts` (`id`, `identifier`, `success`, `ip_address`, `user_agent`, `attempt_time`) VALUES

-- --------------------------------------------------------

--
-- Table structure for table `admin_logs`
--

CREATE TABLE `admin_logs` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) DEFAULT NULL,
  `action` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `details` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin_logs`
--

INSERT INTO `admin_logs` (`id`, `admin_id`, `action`, `description`, `details`, `ip_address`, `user_agent`, `created_at`) VALUES

-- --------------------------------------------------------

--
-- Table structure for table `admin_roles`
--

CREATE TABLE `admin_roles` (
  `id` int(11) NOT NULL,
  `role_name` varchar(50) NOT NULL,
  `description` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin_roles`
--

INSERT INTO `admin_roles` (`id`, `role_name`, `description`) VALUES
(1, 'Head Master', 'Head of the school'),
(2, 'Second Master', 'Deputy head master'),
(3, 'Academic Master', 'Responsible for academic affairs'),
(4, 'Discipline Master', 'Responsible for student discipline'),
(5, 'Class Teacher', 'Class teacher responsibilities'),
(7, 'Dormitory Teacher', 'Responsible for dormitories'),
(12, 'PS', 'Personal Secretary'),
(13, 'Librarian', 'Library management'),
(15, 'Normal Teacher', 'Regular teaching duties'),
(16, 'Maintainance', 'Maintanance of the school');

-- --------------------------------------------------------

--
-- Table structure for table `admin_role_assignments`
--

CREATE TABLE `admin_role_assignments` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `is_primary` tinyint(1) DEFAULT 0,
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin_role_assignments`
--

INSERT INTO `admin_role_assignments` (`id`, `admin_id`, `role_id`, `is_primary`, `assigned_at`) VALUES
(13, 11, 7, 0, '2026-01-07 11:45:53'),
(14, 11, 11, 1, '2026-01-07 11:45:53'),
(15, 13, 16, 1, '2026-01-07 11:53:03'),
(20, 14, 5, 1, '2026-01-09 11:44:30'),
(21, 15, 4, 1, '2026-01-21 15:05:50'),
(0, 25, 16, 1, '2026-02-06 16:21:17'),
(13, 11, 7, 0, '2026-01-07 11:45:53'),
(14, 11, 11, 1, '2026-01-07 11:45:53'),
(15, 13, 16, 1, '2026-01-07 11:53:03'),
(20, 14, 5, 1, '2026-01-09 11:44:30'),
(21, 15, 4, 1, '2026-01-21 15:05:50'),
(0, 25, 16, 1, '2026-02-06 16:21:17'),
(0, 0, 3, 0, '2026-03-08 05:33:05'),
(0, 0, 3, 0, '2026-03-08 05:33:05'),
(0, 0, 4, 1, '2026-03-08 05:33:05'),
(0, 0, 4, 1, '2026-03-08 05:33:05'),
(0, 26, 3, 1, '2026-03-08 05:37:43'),
(0, 29, 12, 1, '2026-03-13 12:11:33'),
(0, 12, 13, 0, '2026-03-13 12:42:26'),
(0, 12, 8, 1, '2026-03-13 12:42:26'),
(0, 31, 1, 1, '2026-03-13 12:57:11'),
(0, 31, 1, 0, '2026-03-13 12:57:43'),
(0, 32, 1, 1, '2026-03-14 14:12:23'),
(0, 17, 2, 1, '2026-03-14 14:12:54'),
(0, 34, 6, 1, '2026-03-14 15:26:23'),
(0, 28, 7, 1, '2026-03-31 18:48:18'),
(0, 36, 13, 0, '2026-04-02 10:36:08'),
(0, 36, 9, 1, '2026-04-02 10:36:08'),
(0, 35, 7, 1, '2026-04-02 14:29:59'),
(0, 35, 14, 0, '2026-04-02 14:29:59');

-- --------------------------------------------------------

--
-- Table structure for table `applications`
--

CREATE TABLE `applications` (
  `id` int(11) NOT NULL,
  `application_number` varchar(50) DEFAULT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `gender` enum('Male','Female') NOT NULL,
  `date_of_birth` date NOT NULL,
  `birth_certificate_number` varchar(50) DEFAULT NULL,
  `phone` varchar(20) NOT NULL,
  `email` varchar(100) NOT NULL,
  `address` text NOT NULL,
  `previous_school` varchar(200) NOT NULL,
  `previous_school_address` varchar(200) NOT NULL,
  `last_exam_year` int(11) NOT NULL,
  `last_exam_grade` varchar(20) NOT NULL,
  `program_applying` varchar(50) NOT NULL,
  `combination` varchar(20) NOT NULL,
  `father_name` varchar(100) DEFAULT NULL,
  `father_phone` varchar(20) DEFAULT NULL,
  `mother_name` varchar(100) DEFAULT NULL,
  `mother_phone` varchar(20) DEFAULT NULL,
  `guardian_name` varchar(100) DEFAULT NULL,
  `guardian_phone` varchar(20) DEFAULT NULL,
  `emergency_contact_name` varchar(100) NOT NULL,
  `emergency_contact_phone` varchar(20) NOT NULL,
  `medical_conditions` text DEFAULT NULL,
  `allergies` text DEFAULT NULL,
  `special_needs` text DEFAULT NULL,
  `application_date` datetime NOT NULL,
  `status` enum('Pending','Under Review','Accepted','Rejected','Waitlisted') DEFAULT 'Pending',
  `review_notes` text DEFAULT NULL,
  `reviewed_by` int(11) DEFAULT NULL,
  `review_date` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `contribution_payments`
--

CREATE TABLE `contribution_payments` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_method` enum('Cash','Mobile Money','Bank Transfer') DEFAULT 'Cash',
  `reference_number` varchar(100) DEFAULT NULL,
  `paid_by` varchar(200) DEFAULT NULL,
  `received_by` int(11) DEFAULT NULL COMMENT 'Admin ID',
  `payment_date` date NOT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `contribution_payments`
--
DELIMITER $$
CREATE TRIGGER `update_equipment_on_payment` AFTER INSERT ON `contribution_payments` FOR EACH ROW BEGIN
    DECLARE total_paid DECIMAL(10,2);
    DECLARE target_amount DECIMAL(10,2) DEFAULT 80000.00;
    
    -- Calculate total paid
    SELECT COALESCE(SUM(amount), 0) INTO total_paid 
    FROM contribution_payments 
    WHERE student_id = NEW.student_id;
    
    -- Update equipment table
    UPDATE student_equipment 
    SET contribution_paid = total_paid,
        contribution_balance = target_amount - total_paid,
        contribution_status = CASE 
            WHEN total_paid >= target_amount THEN 'Paid'
            WHEN total_paid > 0 THEN 'Partially Paid'
            ELSE 'Not Paid'
        END,
        contribution_last_payment = CURRENT_TIMESTAMP
    WHERE student_id = NEW.student_id;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `current_students_by_class`
--

CREATE TABLE `current_students_by_class` (
  `id` int(11) DEFAULT NULL,
  `index_number` varchar(50) DEFAULT NULL,
  `full_name` varchar(302) DEFAULT NULL,
  `sex` enum('Male','Female') DEFAULT NULL,
  `combination` enum('HGE','HGL','HGK','HKL','KLF','EGM','HLF','HGF') DEFAULT NULL,
  `class` enum('Form Five','Form Six','Leavers','Graduated') DEFAULT NULL,
  `graduation_status` enum('Active','Form Five','Form Six','Graduated','Left') DEFAULT NULL,
  `promotion_status` enum('Not Promoted','Promoted to Form Six','Retained') DEFAULT NULL,
  `date_of_admission` date DEFAULT NULL,
  `parent_name` varchar(200) DEFAULT NULL,
  `parent_phone` varchar(20) DEFAULT NULL,
  `dormitory_id` int(11) DEFAULT NULL,
  `dorm_name` varchar(50) DEFAULT NULL,
  `room_id` int(11) DEFAULT NULL,
  `room_label` varchar(20) DEFAULT NULL,
  `equipment_status` enum('Complete','Incomplete','None') DEFAULT NULL,
  `contribution_status` enum('Paid','Partially Paid','Not Paid') DEFAULT NULL,
  `is_leaver` tinyint(1) DEFAULT NULL,
  `year_left` year(4) DEFAULT NULL,
  `student_active` tinyint(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `discipline_records`
--

CREATE TABLE `discipline_records` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `list_type` enum('white','black') NOT NULL COMMENT 'White list = Good, Black list = Disciplinary issues',
  `record_type` enum('warning','appreciation','suspension','reprimand','commendation','expulsion') NOT NULL,
  `short_note` text NOT NULL,
  `file_path` varchar(500) DEFAULT NULL,
  `file_type` enum('image','video','audio','document','other') DEFAULT NULL,
  `file_name` varchar(255) DEFAULT NULL,
  `file_size` int(11) DEFAULT NULL COMMENT 'Size in bytes',
  `recorded_by` int(11) NOT NULL COMMENT 'Admin who recorded',
  `is_visible_to_student` tinyint(1) DEFAULT 1 COMMENT 'Can student see this?',
  `severity_level` enum('low','medium','high','critical') DEFAULT 'medium',
  `follow_up_required` tinyint(1) DEFAULT 0,
  `follow_up_due_date` date DEFAULT NULL,
  `follow_up_completed` tinyint(1) DEFAULT 0,
  `follow_up_notes` text DEFAULT NULL,
  `status` enum('active','resolved','archived','deleted') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `discipline_records`
--

INSERT INTO `discipline_records` (`id`, `student_id`, `list_type`, `record_type`, `short_note`, `file_path`, `file_type`, `file_name`, `file_size`, `recorded_by`, `is_visible_to_student`, `severity_level`, `follow_up_required`, `follow_up_due_date`, `follow_up_completed`, `follow_up_notes`, `status`, `created_at`, `updated_at`) VALUES
(0, 39, 'white', 'appreciation', 'good', NULL, NULL, NULL, NULL, 12, 1, 'high', 0, NULL, 0, NULL, 'active', '2026-03-08 01:35:53', '2026-03-08 01:35:53'),
(0, 221, 'black', 'reprimand', 'too bad', NULL, NULL, NULL, NULL, 12, 1, 'low', 0, NULL, 0, NULL, 'active', '2026-03-08 01:36:27', '2026-03-08 01:36:27');

-- --------------------------------------------------------

--
-- Table structure for table `discipline_statistics`
--

CREATE TABLE `discipline_statistics` (
  `student_id` int(11) DEFAULT NULL,
  `student_name` varchar(201) DEFAULT NULL,
  `index_number` varchar(50) DEFAULT NULL,
  `class` enum('Form Five','Form Six','Leavers','Graduated') DEFAULT NULL,
  `combination` enum('HGE','HGL','HGK','HKL','KLF','EGM','HLF','HGF') DEFAULT NULL,
  `sex` enum('Male','Female') DEFAULT NULL,
  `is_leaver` tinyint(1) DEFAULT NULL,
  `student_status` tinyint(1) DEFAULT NULL,
  `blacklist_count` bigint(21) DEFAULT NULL,
  `whitelist_count` bigint(21) DEFAULT NULL,
  `critical_issues` bigint(21) DEFAULT NULL,
  `pending_followups` bigint(21) DEFAULT NULL,
  `last_blacklist_entry` timestamp NULL DEFAULT NULL,
  `last_whitelist_entry` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `dormitories`
--

CREATE TABLE `dormitories` (
  `id` int(11) NOT NULL,
  `dorm_name` varchar(50) NOT NULL,
  `dorm_type` enum('Male','Female') NOT NULL,
  `rooms_count` int(11) NOT NULL,
  `capacity_per_room` int(11) NOT NULL,
  `total_capacity` int(11) NOT NULL,
  `current_occupancy` int(11) DEFAULT 0,
  `description` text DEFAULT NULL,
  `status` enum('Active','Full','Maintenance','Closed') DEFAULT 'Active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `dormitories`
--

INSERT INTO `dormitories` (`id`, `dorm_name`, `dorm_type`, `rooms_count`, `capacity_per_room`, `total_capacity`, `current_occupancy`, `description`, `status`, `created_at`, `updated_at`) VALUES
(1, 'Safina', 'Female', 16, 10, 160, 0, 'Safina Female Dormitory - Rooms A1 to B8, 10 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-08 18:34:02'),
(2, 'Samia', 'Female', 20, 6, 120, 0, 'Samia Female Dormitory - Rooms A1 to B10, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-08 18:34:16'),
(3, 'Magufuli', 'Male', 20, 6, 120, 0, 'Magufuli Male Dormitory - Rooms A1 to B10, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-07 09:36:30'),
(4, 'Sokoine', 'Male', 20, 6, 120, 0, 'Sokoine Male Dormitory - Rooms A1 to B10, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-07 09:03:34'),
(5, 'Mwandu', 'Male', 20, 6, 120, 0, 'Mwandu Male Dormitory - Rooms A1 to B10, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-03-08 02:40:47'),
(6, 'Nyerere', 'Male', 10, 12, 120, 0, 'Nyerere Male Dormitory - Rooms A1 to A10, 12 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-07 09:03:57'),
(7, 'Kisutu Juu', 'Male', 5, 6, 30, 0, 'Kisutu Juu Male Dormitory - Rooms A1 to A5, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-08 18:32:01'),
(8, 'Kisutu Bombani', 'Male', 2, 12, 24, 1, 'Kisutu Bombani Male Dormitory - Rooms A1 to B1, 12 students per room', 'Active', '2026-02-07 07:03:59', '2026-04-01 22:06:42'),
(9, 'Kisutu Chini', 'Male', 2, 6, 12, 0, 'Kisutu Chini Male Dormitory - Rooms A1 to B1, 6 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-09 17:49:47'),
(10, 'Kisutu Prison', 'Male', 7, 2, 14, 0, 'Kisutu Prison Male Dormitory - Rooms A1 to A7, 2 students per room', 'Active', '2026-02-07 07:03:59', '2026-02-09 17:49:53');

-- --------------------------------------------------------

--
-- Stand-in structure for view `dormitory_occupancy_summary`
-- (See below for the actual view)
--
CREATE TABLE `dormitory_occupancy_summary` (
`id` int(11)
,`dorm_name` varchar(50)
,`dorm_type` enum('Male','Female')
,`rooms_count` int(11)
,`capacity_per_room` int(11)
,`total_capacity` int(11)
,`current_occupancy` int(11)
,`available_beds` bigint(12)
,`occupancy_percentage` decimal(16,2)
,`dormitory_status` enum('Active','Full','Maintenance','Closed')
,`description` text
,`total_rooms` bigint(21)
,`available_rooms` bigint(21)
,`full_rooms` bigint(21)
,`maintenance_rooms` bigint(21)
,`active_student_count` bigint(21)
);

-- --------------------------------------------------------

--
-- Table structure for table `dormitory_rooms`
--

CREATE TABLE `dormitory_rooms` (
  `id` int(11) NOT NULL,
  `dormitory_id` int(11) NOT NULL,
  `room_number` varchar(10) NOT NULL,
  `room_label` varchar(20) NOT NULL,
  `capacity` int(11) NOT NULL,
  `current_occupancy` int(11) DEFAULT 0,
  `status` enum('Available','Full','Maintenance') DEFAULT 'Available',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `dormitory_rooms`
--

INSERT INTO `dormitory_rooms` (`id`, `dormitory_id`, `room_number`, `room_label`, `capacity`, `current_occupancy`, `status`, `created_at`, `updated_at`) VALUES
(1, 1, 'A1', 'Safina A1', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:34:02'),
(2, 1, 'A2', 'Safina A2', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(3, 1, 'A3', 'Safina A3', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(4, 1, 'A4', 'Safina A4', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(5, 1, 'A5', 'Safina A5', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(6, 1, 'A6', 'Safina A6', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(7, 1, 'A7', 'Safina A7', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(8, 1, 'A8', 'Safina A8', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(9, 1, 'B1', 'Safina B1', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(10, 1, 'B2', 'Safina B2', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:33:02'),
(11, 1, 'B3', 'Safina B3', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(12, 1, 'B4', 'Safina B4', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(13, 1, 'B5', 'Safina B5', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(14, 1, 'B6', 'Safina B6', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(15, 1, 'B7', 'Safina B7', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(16, 1, 'B8', 'Safina B8', 10, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(17, 2, 'A1', 'Samia A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:34:08'),
(18, 2, 'A2', 'Samia A2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(19, 2, 'A3', 'Samia A3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(20, 2, 'A4', 'Samia A4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(21, 2, 'A5', 'Samia A5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(22, 2, 'A6', 'Samia A6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(23, 2, 'A7', 'Samia A7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(24, 2, 'A8', 'Samia A8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(25, 2, 'A9', 'Samia A9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(26, 2, 'A10', 'Samia A10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(27, 2, 'B1', 'Samia B1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(28, 2, 'B2', 'Samia B2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(29, 2, 'B3', 'Samia B3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(30, 2, 'B4', 'Samia B4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(31, 2, 'B5', 'Samia B5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:34:16'),
(32, 2, 'B6', 'Samia B6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(33, 2, 'B7', 'Samia B7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(34, 2, 'B8', 'Samia B8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(35, 2, 'B9', 'Samia B9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(36, 2, 'B10', 'Samia B10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(37, 3, 'A1', 'Magufuli A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 09:36:30'),
(38, 3, 'A2', 'Magufuli A2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(39, 3, 'A3', 'Magufuli A3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(40, 3, 'A4', 'Magufuli A4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(41, 3, 'A5', 'Magufuli A5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(42, 3, 'A6', 'Magufuli A6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(43, 3, 'A7', 'Magufuli A7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(44, 3, 'A8', 'Magufuli A8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(45, 3, 'A9', 'Magufuli A9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(46, 3, 'A10', 'Magufuli A10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(47, 3, 'B1', 'Magufuli B1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(48, 3, 'B2', 'Magufuli B2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(49, 3, 'B3', 'Magufuli B3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(50, 3, 'B4', 'Magufuli B4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(51, 3, 'B5', 'Magufuli B5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(52, 3, 'B6', 'Magufuli B6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(53, 3, 'B7', 'Magufuli B7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(54, 3, 'B8', 'Magufuli B8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(55, 3, 'B9', 'Magufuli B9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(56, 3, 'B10', 'Magufuli B10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(57, 4, 'A1', 'Sokoine A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:49:45'),
(58, 4, 'A2', 'Sokoine A2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(59, 4, 'A3', 'Sokoine A3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(60, 4, 'A4', 'Sokoine A4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(61, 4, 'A5', 'Sokoine A5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(62, 4, 'A6', 'Sokoine A6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(63, 4, 'A7', 'Sokoine A7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(64, 4, 'A8', 'Sokoine A8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(65, 4, 'A9', 'Sokoine A9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(66, 4, 'A10', 'Sokoine A10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(67, 4, 'B1', 'Sokoine B1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(68, 4, 'B2', 'Sokoine B2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(69, 4, 'B3', 'Sokoine B3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(70, 4, 'B4', 'Sokoine B4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(71, 4, 'B5', 'Sokoine B5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(72, 4, 'B6', 'Sokoine B6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(73, 4, 'B7', 'Sokoine B7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(74, 4, 'B8', 'Sokoine B8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(75, 4, 'B9', 'Sokoine B9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(76, 4, 'B10', 'Sokoine B10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(77, 5, 'A1', 'Mwandu A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:32:23'),
(78, 5, 'A2', 'Mwandu A2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(79, 5, 'A3', 'Mwandu A3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(80, 5, 'A4', 'Mwandu A4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(81, 5, 'A5', 'Mwandu A5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(82, 5, 'A6', 'Mwandu A6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(83, 5, 'A7', 'Mwandu A7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(84, 5, 'A8', 'Mwandu A8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(85, 5, 'A9', 'Mwandu A9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(86, 5, 'A10', 'Mwandu A10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(87, 5, 'B1', 'Mwandu B1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-03-08 02:40:47'),
(88, 5, 'B2', 'Mwandu B2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(89, 5, 'B3', 'Mwandu B3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(90, 5, 'B4', 'Mwandu B4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(91, 5, 'B5', 'Mwandu B5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(92, 5, 'B6', 'Mwandu B6', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(93, 5, 'B7', 'Mwandu B7', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(94, 5, 'B8', 'Mwandu B8', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(95, 5, 'B9', 'Mwandu B9', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(96, 5, 'B10', 'Mwandu B10', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(97, 6, 'A1', 'Nyerere A1', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:52:18'),
(98, 6, 'A2', 'Nyerere A2', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(99, 6, 'A3', 'Nyerere A3', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(100, 6, 'A4', 'Nyerere A4', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(101, 6, 'A5', 'Nyerere A5', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(102, 6, 'A6', 'Nyerere A6', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(103, 6, 'A7', 'Nyerere A7', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(104, 6, 'A8', 'Nyerere A8', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(105, 6, 'A9', 'Nyerere A9', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(106, 6, 'A10', 'Nyerere A10', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(107, 7, 'A1', 'Kisutu Juu A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-08 18:32:01'),
(108, 7, 'A2', 'Kisutu Juu A2', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(109, 7, 'A3', 'Kisutu Juu A3', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(110, 7, 'A4', 'Kisutu Juu A4', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(111, 7, 'A5', 'Kisutu Juu A5', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(112, 8, 'A1', 'Kisutu Bombani A1', 12, 1, 'Available', '2026-02-07 07:03:59', '2026-04-01 22:06:42'),
(113, 8, 'B1', 'Kisutu Bombani B1', 12, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(114, 9, 'A1', 'Kisutu Chini A1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-09 17:49:47'),
(115, 9, 'B1', 'Kisutu Chini B1', 6, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(116, 10, 'A1', 'Kisutu Prison A1', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-09 17:49:53'),
(117, 10, 'A2', 'Kisutu Prison A2', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(118, 10, 'A3', 'Kisutu Prison A3', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(119, 10, 'A4', 'Kisutu Prison A4', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(120, 10, 'A5', 'Kisutu Prison A5', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(121, 10, 'A6', 'Kisutu Prison A6', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59'),
(122, 10, 'A7', 'Kisutu Prison A7', 2, 0, 'Available', '2026-02-07 07:03:59', '2026-02-07 07:03:59');

--
-- Triggers `dormitory_rooms`
--
DELIMITER $$
CREATE TRIGGER `log_room_status_change` AFTER UPDATE ON `dormitory_rooms` FOR EACH ROW BEGIN
    -- Log only when status actually changes (not NULL)
    IF OLD.status != NEW.status AND OLD.status IS NOT NULL AND NEW.status IS NOT NULL THEN
        INSERT INTO room_status_logs (room_id, old_status, new_status, notes)
        VALUES (NEW.id, OLD.status, NEW.status, 'Status changed manually');
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_dormitory_occupancy` AFTER UPDATE ON `dormitory_rooms` FOR EACH ROW BEGIN
    DECLARE v_total_occupancy INT DEFAULT 0;
    DECLARE v_total_capacity INT DEFAULT 0;
    
    -- Only run if occupancy changed
    IF OLD.current_occupancy != NEW.current_occupancy THEN
        -- Calculate total occupancy for the dormitory (prevent negatives)
        SELECT COALESCE(SUM(GREATEST(current_occupancy, 0)), 0) INTO v_total_occupancy
        FROM dormitory_rooms
        WHERE dormitory_id = NEW.dormitory_id;
        
        -- Get total capacity
        SELECT total_capacity INTO v_total_capacity
        FROM dormitories
        WHERE id = NEW.dormitory_id;
        
        -- Update dormitory occupancy (ensure it doesn't exceed capacity)
        UPDATE dormitories 
        SET current_occupancy = LEAST(v_total_occupancy, v_total_capacity),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.dormitory_id;
        
        -- Update dormitory status
        UPDATE dormitories 
        SET status = CASE 
            WHEN v_total_occupancy >= v_total_capacity THEN 'Full'
            ELSE 'Active'
        END
        WHERE id = NEW.dormitory_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_room_status_auto` AFTER UPDATE ON `dormitory_rooms` FOR EACH ROW BEGIN
    -- Only run if occupancy changed
    IF OLD.current_occupancy != NEW.current_occupancy THEN
        -- Update room status based on occupancy (with bounds checking)
        IF NEW.current_occupancy >= NEW.capacity THEN
            UPDATE dormitory_rooms 
            SET status = 'Full',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.id
            AND status != 'Maintenance';
            
            -- Log status change
            INSERT INTO room_status_logs (room_id, old_status, new_status, notes)
            VALUES (NEW.id, OLD.status, 'Full', CONCAT('Auto-changed: Room reached capacity (', NEW.current_occupancy, '/', NEW.capacity, ')'));
            
        ELSEIF NEW.current_occupancy < NEW.capacity AND NEW.status = 'Full' THEN
            UPDATE dormitory_rooms 
            SET status = 'Available',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.id;
            
            -- Log status change
            INSERT INTO room_status_logs (room_id, old_status, new_status, notes)
            VALUES (NEW.id, 'Full', 'Available', CONCAT('Auto-changed: Room has space (', NEW.current_occupancy, '/', NEW.capacity, ')'));
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `equipment_transactions`
--

CREATE TABLE `equipment_transactions` (
  `id` int(11) NOT NULL,
  `equipment_id` int(11) NOT NULL,
  `transaction_type` enum('IN','OUT') NOT NULL,
  `quantity` int(11) NOT NULL,
  `previous_quantity` int(11) NOT NULL,
  `new_quantity` int(11) NOT NULL,
  `reason` text NOT NULL,
  `performed_by` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `equipment_updates`
--

CREATE TABLE `equipment_updates` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `equipment_type` varchar(50) NOT NULL,
  `quantity` int(11) DEFAULT 1,
  `action` enum('Added','Removed','Updated') DEFAULT 'Added',
  `updated_by` int(11) DEFAULT NULL COMMENT 'Admin ID',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `exam_types`
--

CREATE TABLE `exam_types` (
  `id` int(11) NOT NULL,
  `exam_name` varchar(100) NOT NULL,
  `exam_code` varchar(20) NOT NULL,
  `term` varchar(20) DEFAULT NULL,
  `year` year(4) NOT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `description` text DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `updated_by` int(11) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `form_level` enum('Form Five','Form Six') NOT NULL DEFAULT 'Form Five'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `exam_types`
--

INSERT INTO `exam_types` (`id`, `exam_name`, `exam_code`, `term`, `year`, `is_active`, `created_at`, `description`, `created_by`, `updated_by`, `updated_at`, `form_level`) VALUES
(18, 'school', 'm34', 'Term 1', '2026', 1, '2026-04-02 13:25:32', '', 32, 32, '2026-04-02 14:19:39', 'Form Six'),
(20, 'hello_exam', '89', 'Term 1', '2026', 1, '2026-04-03 05:09:06', '', 32, NULL, '2026-04-03 05:09:14', 'Form Five');

-- --------------------------------------------------------

--
-- Table structure for table `food_stock`
--

CREATE TABLE `food_stock` (
  `id` int(11) NOT NULL,
  `item_name` varchar(255) NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `unit` varchar(50) NOT NULL,
  `date_added` date DEFAULT curdate(),
  `description` text DEFAULT NULL,
  `status` enum('available','low','out_of_stock') DEFAULT 'available',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `food_stock`
--
DELIMITER $$
CREATE TRIGGER `update_food_status` BEFORE UPDATE ON `food_stock` FOR EACH ROW BEGIN
    IF NEW.quantity <= 0 THEN
        SET NEW.status = 'out_of_stock';
    ELSEIF NEW.quantity <= 50 THEN
        SET NEW.status = 'low';
    ELSE
        SET NEW.status = 'available';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `food_stock_history`
--

CREATE TABLE `food_stock_history` (
  `id` int(11) NOT NULL,
  `food_id` int(11) NOT NULL,
  `old_quantity` decimal(10,2) DEFAULT NULL,
  `new_quantity` decimal(10,2) DEFAULT NULL,
  `change_type` enum('add','remove','adjust','initial') NOT NULL,
  `reason` text DEFAULT NULL,
  `changed_by` int(11) DEFAULT NULL,
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `form_five_promotion_candidates`
--

CREATE TABLE `form_five_promotion_candidates` (
  `id` int(11) DEFAULT NULL,
  `index_number` varchar(50) DEFAULT NULL,
  `full_name` varchar(201) DEFAULT NULL,
  `sex` enum('Male','Female') DEFAULT NULL,
  `combination` enum('HGE','HGL','HGK','HKL','KLF','EGM','HLF','HGF') DEFAULT NULL,
  `date_of_birth` date DEFAULT NULL,
  `date_of_admission` date DEFAULT NULL,
  `parent_name` varchar(200) DEFAULT NULL,
  `parent_phone` varchar(20) DEFAULT NULL,
  `equipment_status` enum('Complete','Incomplete','None') DEFAULT NULL,
  `contribution_status` enum('Paid','Partially Paid','Not Paid') DEFAULT NULL,
  `blacklist_entries` bigint(21) DEFAULT NULL,
  `whitelist_entries` bigint(21) DEFAULT NULL,
  `is_leaver` tinyint(1) DEFAULT NULL,
  `graduation_status` enum('Active','Form Five','Form Six','Graduated','Left') DEFAULT NULL,
  `promotion_eligibility` varchar(22) DEFAULT NULL,
  `eligibility_notes` varchar(21) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `form_five_results`
--

CREATE TABLE `form_five_results` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `exam_type_id` int(11) NOT NULL,
  `ac` int(11) DEFAULT NULL,
  `htm` int(11) DEFAULT NULL,
  `his` int(11) DEFAULT NULL,
  `geo` int(11) DEFAULT NULL,
  `kisw` int(11) DEFAULT NULL,
  `eng` int(11) DEFAULT NULL,
  `b_math` int(11) DEFAULT NULL,
  `adv_m` int(11) DEFAULT NULL,
  `eco` int(11) DEFAULT NULL,
  `fren` int(11) DEFAULT NULL,
  `total_points` int(11) DEFAULT NULL,
  `average` decimal(5,2) DEFAULT NULL,
  `division` varchar(20) DEFAULT NULL,
  `entered_by` int(11) DEFAULT NULL,
  `entered_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `subject_teacher_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `form_five_results`
--

INSERT INTO `form_five_results` (`id`, `student_id`, `exam_type_id`, `ac`, `htm`, `his`, `geo`, `kisw`, `eng`, `b_math`, `adv_m`, `eco`, `fren`, `total_points`, `average`, `division`, `entered_by`, `entered_at`, `updated_at`, `subject_teacher_id`) VALUES
(66, 408, 20, 55, 66, 88, 99, NULL, NULL, 66, NULL, 88, NULL, 3, 77.00, 'Division I', 32, '2026-04-03 05:09:44', '2026-04-03 05:11:37', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `form_six_results`
--

CREATE TABLE `form_six_results` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `exam_type_id` int(11) NOT NULL,
  `ac` int(11) DEFAULT NULL,
  `htm` int(11) DEFAULT NULL,
  `b_math` int(11) DEFAULT NULL,
  `his` int(11) DEFAULT NULL,
  `geo` int(11) DEFAULT NULL,
  `kisw` int(11) DEFAULT NULL,
  `eng` int(11) DEFAULT NULL,
  `adv_m` int(11) DEFAULT NULL,
  `eco` int(11) DEFAULT NULL,
  `fren` int(11) DEFAULT NULL,
  `total_points` int(11) DEFAULT NULL,
  `average` decimal(5,2) DEFAULT NULL,
  `division` varchar(20) DEFAULT NULL,
  `entered_by` int(11) DEFAULT NULL,
  `entered_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `subject_teacher_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `form_six_results`
--

INSERT INTO `form_six_results` (`id`, `student_id`, `exam_type_id`, `ac`, `htm`, `b_math`, `his`, `geo`, `kisw`, `eng`, `adv_m`, `eco`, `fren`, `total_points`, `average`, `division`, `entered_by`, `entered_at`, `updated_at`, `subject_teacher_id`) VALUES
(1, 18, 18, 33, 18, 66, 88, 18, NULL, NULL, NULL, 77, NULL, 10, 50.00, 'Division II', 32, '2026-04-02 14:10:21', '2026-04-03 04:45:46', NULL),
(2, 9, 18, 66, 77, 43, 77, 22, NULL, NULL, NULL, 43, NULL, 7, 54.67, 'Division I', 32, '2026-04-02 14:12:11', '2026-04-02 14:16:58', NULL),
(3, 189, 18, 55, 66, 36, 88, 99, NULL, NULL, NULL, 77, NULL, 4, 70.17, 'Division I', 32, '2026-04-02 14:12:22', '2026-04-02 18:11:52', NULL),
(5, 69, 18, 66, 11, 40, 33, 5, NULL, NULL, NULL, 99, NULL, 9, 42.33, 'Division I', 32, '2026-04-02 14:21:55', '2026-04-02 18:11:56', NULL),
(6, 93, 18, 66, 11, 56, 88, 5, NULL, NULL, NULL, 98, NULL, 5, 54.00, 'Division I', 32, '2026-04-02 14:22:17', '2026-04-02 18:12:28', NULL),
(7, 61, 18, 55, 88, 88, 12, 6, NULL, NULL, NULL, 45, NULL, 6, 49.00, 'Division I', 32, '2026-04-02 15:22:00', '2026-04-02 18:16:27', NULL),
(8, 229, 18, 66, 66, 90, 56, 6, NULL, NULL, NULL, 33, NULL, 7, 52.83, 'Division I', 32, '2026-04-02 15:22:01', '2026-04-02 18:16:21', NULL),
(9, 197, 18, 0, 77, NULL, 33, 78, NULL, NULL, NULL, NULL, NULL, 11, 62.67, 'Division II', 32, '2026-04-02 15:22:01', '2026-04-03 03:58:39', NULL),
(10, 205, 18, 88, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 88.00, NULL, 32, '2026-04-02 15:22:01', '2026-04-03 04:46:28', NULL),
(11, 85, 18, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 32, '2026-04-02 15:22:03', '2026-04-02 18:16:56', NULL),
(12, 53, 18, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 32, '2026-04-02 15:22:03', '2026-04-02 18:17:02', NULL),
(13, 190, 18, NULL, NULL, NULL, 17, 6, NULL, 88, NULL, NULL, NULL, 15, 37.00, 'Division III', 32, '2026-04-02 15:22:03', '2026-04-03 05:37:35', NULL),
(14, 230, 18, NULL, NULL, NULL, NULL, 66, NULL, NULL, NULL, NULL, NULL, 3, 66.00, 'Division I', 32, '2026-04-02 15:22:04', '2026-04-02 15:22:04', NULL),
(15, 13, 18, NULL, NULL, NULL, NULL, 6, NULL, 66, NULL, NULL, NULL, 10, 36.00, 'Division II', 32, '2026-04-02 15:22:04', '2026-04-02 15:23:55', NULL),
(16, 46, 18, NULL, NULL, NULL, NULL, 66, NULL, 6, NULL, NULL, NULL, 10, 36.00, 'Division II', 32, '2026-04-02 15:23:58', '2026-04-02 15:24:00', NULL),
(17, 70, 18, 10, 9, NULL, 8, 7, NULL, 20, NULL, NULL, NULL, 21, 10.80, 'Division 0', 32, '2026-04-02 15:24:03', '2026-04-03 05:37:58', NULL),
(18, 54, 18, 7, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 7.00, NULL, 32, '2026-04-03 05:38:07', '2026-04-03 05:38:08', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `game_types`
--

CREATE TABLE `game_types` (
  `id` int(11) NOT NULL,
  `game_name` varchar(50) NOT NULL,
  `description` text DEFAULT NULL,
  `status` enum('Active','Inactive') DEFAULT 'Active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `color_code` varchar(7) DEFAULT '#3B9DB3'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `game_types`
--

INSERT INTO `game_types` (`id`, `game_name`, `description`, `status`, `created_at`, `color_code`) VALUES
(1, 'Football', 'Soccer/Football matches', 'Active', '2026-03-31 16:51:42', '#28a745'),
(2, 'Netball', 'Netball matches', 'Active', '2026-03-31 16:51:42', '#dc3545'),
(3, 'Handball', 'Handball matches', 'Active', '2026-03-31 16:51:42', '#ffc107'),
(4, 'Volleyball', 'Volleyball matches', 'Active', '2026-03-31 16:51:42', '#17a2b8');

-- --------------------------------------------------------

--
-- Table structure for table `library_assignments`
--

CREATE TABLE `library_assignments` (
  `id` int(11) NOT NULL,
  `user_type` enum('staff','student') NOT NULL,
  `user_id` int(11) NOT NULL,
  `user_name` varchar(255) NOT NULL,
  `book_title` varchar(255) NOT NULL,
  `book_number` varchar(50) NOT NULL,
  `quantity` varchar(20) NOT NULL,
  `assigned_date` date NOT NULL,
  `short_note` text DEFAULT NULL,
  `status` enum('borrowed','returned') DEFAULT 'borrowed',
  `return_date` date DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `library_assignments`
--

INSERT INTO `library_assignments` (`id`, `user_type`, `user_id`, `user_name`, `book_title`, `book_number`, `quantity`, `assigned_date`, `short_note`, `status`, `return_date`, `created_at`, `updated_at`) VALUES
(6, 'staff', 26, 'Franc peter', 'history', '12', '5', '2026-03-14', 'none', 'borrowed', NULL, '2026-03-14 13:07:53', '2026-03-14 13:07:53'),
(7, 'student', 74, 'Abdallah Mpemba', 'geography', '1', '2 books, 2 pastpaper', '2026-03-14', '', 'borrowed', NULL, '2026-03-14 13:09:58', '2026-03-14 13:09:58');

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_assignments`
--

CREATE TABLE `maintenance_assignments` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'Reference to students table',
  `item_id` int(11) NOT NULL COMMENT 'Reference to maintenance_items table',
  `assignment_type` varchar(20) NOT NULL COMMENT 'Type of assignment: table, chair',
  `assigned_by` int(11) DEFAULT NULL COMMENT 'Admin who made the assignment',
  `assigned_date` date NOT NULL,
  `due_date` date DEFAULT NULL COMMENT 'Expected return date',
  `status` varchar(20) DEFAULT 'active' COMMENT 'active, returned, cancelled',
  `return_date` date DEFAULT NULL COMMENT 'Date when item was returned',
  `return_condition` varchar(20) DEFAULT NULL COMMENT 'Condition when returned: good, damaged, lost',
  `return_notes` text DEFAULT NULL COMMENT 'Notes about the return',
  `notes` text DEFAULT NULL COMMENT 'General notes about the assignment',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_assignments`
--

INSERT INTO `maintenance_assignments` (`id`, `student_id`, `item_id`, `assignment_type`, `assigned_by`, `assigned_date`, `due_date`, `status`, `return_date`, `return_condition`, `return_notes`, `notes`, `created_at`, `updated_at`) VALUES
(1, 61, 1, 'table', 12, '2026-02-07', '2026-03-09', 'returned', '2026-02-07', 'good', '', '', '2026-02-07 13:18:01', '2026-02-07 13:19:46'),
(2, 61, 2, 'chair', 12, '2026-02-07', '2026-03-09', 'returned', '2026-02-07', 'good', '', '', '2026-02-07 13:18:01', '2026-02-07 13:19:57'),
(3, 61, 5, 'table', 14, '2026-02-07', '2026-02-07', 'returned', '2026-02-07', 'good', 'Auto-returned: Transferred from Form Five', '', '2026-02-07 14:34:04', '2026-02-07 14:34:57'),
(4, 61, 4, 'chair', 14, '2026-02-07', '2026-02-07', 'returned', '2026-02-07', 'good', 'Auto-returned: Transferred from Form Five', '', '2026-02-07 14:34:04', '2026-02-07 14:34:57'),
(5, 61, 1, 'table', 14, '2026-02-07', '2026-03-09', 'returned', '2026-02-07', 'good', 'Auto-returned: Transferred from Form Five', '', '2026-02-07 14:41:47', '2026-02-07 14:45:58'),
(6, 61, 2, 'chair', 14, '2026-02-07', '2026-03-09', 'returned', '2026-02-07', 'good', 'Auto-returned: Transferred from Form Five', '', '2026-02-07 14:41:47', '2026-02-07 14:45:58'),
(7, 18, 1, 'table', 12, '2026-02-09', '2026-03-11', 'returned', '2026-02-09', 'good', '', '', '2026-02-09 07:28:36', '2026-02-09 17:57:27'),
(8, 18, 2, 'chair', 12, '2026-02-09', '2026-03-11', 'returned', '2026-02-09', 'good', 'Force returned by admin', '', '2026-02-09 07:28:36', '2026-02-09 17:57:05'),
(9, 246, 1, 'table', 12, '2026-03-08', '2026-04-07', 'returned', '2026-03-08', 'good', '', '', '2026-03-08 02:35:00', '2026-03-08 02:37:27'),
(10, 246, 2, 'chair', 12, '2026-03-08', '2026-04-07', 'returned', '2026-03-08', 'good', '', '', '2026-03-08 02:35:00', '2026-03-08 02:37:06'),
(11, 246, 1, 'table', 12, '2026-03-08', '2027-05-10', 'returned', '2026-03-08', 'good', '', '', '2026-03-08 02:38:15', '2026-03-08 02:38:40'),
(12, 246, 2, 'chair', 12, '2026-03-08', '2027-05-10', 'returned', '2026-03-08', 'good', '', '', '2026-03-08 02:38:15', '2026-03-08 02:38:43');

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_items`
--

CREATE TABLE `maintenance_items` (
  `id` int(11) NOT NULL,
  `item_code` varchar(50) NOT NULL COMMENT 'Unique item identifier (e.g., TBL-001, CHR-001)',
  `item_type` varchar(20) NOT NULL COMMENT 'Type of item: table, chair, other',
  `description` text DEFAULT NULL COMMENT 'Item description',
  `location` varchar(100) DEFAULT NULL COMMENT 'Current location of the item',
  `status` varchar(20) DEFAULT 'available' COMMENT 'Item status: available, assigned, damaged, under_maintenance, lost',
  `signed_at` date DEFAULT NULL COMMENT 'Date when item was added to inventory',
  `last_maintenance` date DEFAULT NULL COMMENT 'Date of last maintenance',
  `notes` text DEFAULT NULL COMMENT 'Additional notes about the item',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_items`
--

INSERT INTO `maintenance_items` (`id`, `item_code`, `item_type`, `description`, `location`, `status`, `signed_at`, `last_maintenance`, `notes`, `created_at`, `updated_at`) VALUES
(1, 't556', 'table', '', 'dar es salaam', 'available', '2026-02-07', NULL, '', '2026-02-07 13:15:13', '2026-03-08 02:38:40'),
(2, 'c44', 'chair', '', '', 'available', '2026-02-07', NULL, '', '2026-02-07 13:15:39', '2026-03-08 02:38:43'),
(3, 't559', 'table', '', '', 'available', '2026-02-07', NULL, '', '2026-02-07 13:15:55', '2026-02-07 13:15:55'),
(4, 'c45', 'chair', '', '', 'available', '2026-02-07', NULL, '', '2026-02-07 13:16:09', '2026-02-09 17:57:35'),
(5, 't557', 'table', '', '', 'available', '2026-02-07', NULL, '', '2026-02-07 13:16:23', '2026-02-09 17:57:33'),
(6, 'c48', 'chair', '', '', 'available', '2026-02-07', NULL, '', '2026-02-07 13:16:44', '2026-02-07 13:16:44');

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_logs`
--

CREATE TABLE `maintenance_logs` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL COMMENT 'Reference to maintenance_items table',
  `log_type` varchar(50) NOT NULL COMMENT 'Type of log: assignment, return, damage, repair, maintenance',
  `user_type` varchar(20) DEFAULT NULL COMMENT 'Type of user: student, staff, admin',
  `user_id` int(11) DEFAULT NULL COMMENT 'Reference to students or admins table',
  `admin_id` int(11) NOT NULL COMMENT 'Admin who performed the action',
  `description` text NOT NULL COMMENT 'Description of the action',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_logs`
--

INSERT INTO `maintenance_logs` (`id`, `item_id`, `log_type`, `user_type`, `user_id`, `admin_id`, `description`, `created_at`) VALUES
(23, 1, 'assignment', 'student', 18, 12, 'Assigned t556 (table) to student: JANETH WECH', '2026-02-09 07:28:36'),
(24, 2, 'assignment', 'student', 18, 12, 'Assigned c44 (chair) to student: JANETH WECH', '2026-02-09 07:28:36'),
(25, 5, 'assignment', 'staff', 15, 12, 'Assigned t557 (table) to staff: aujenia leo', '2026-02-09 17:54:02'),
(26, 4, 'assignment', 'staff', 15, 12, 'Assigned c45 (chair) to staff: aujenia leo', '2026-02-09 17:54:02'),
(27, 2, 'return', 'student', 18, 12, 'Force returned c44 from student: JANETH WECH by admin', '2026-02-09 17:57:05'),
(28, 1, 'return', 'student', 18, 12, 'Returned t556 from student: JANETH WECH. Condition: good', '2026-02-09 17:57:27'),
(29, 5, 'return', 'staff', 15, 12, 'Returned t557 from staff: aujenia leo. Condition: good', '2026-02-09 17:57:33'),
(30, 4, 'return', 'staff', 15, 12, 'Returned c45 from staff: aujenia leo. Condition: good', '2026-02-09 17:57:35'),
(31, 1, 'assignment', 'student', 246, 12, 'Assigned t556 (table) to student: Samuel Mkumbo', '2026-03-08 02:35:00'),
(32, 2, 'assignment', 'student', 246, 12, 'Assigned c44 (chair) to student: Samuel Mkumbo', '2026-03-08 02:35:00'),
(33, 2, 'return', 'student', 246, 12, 'Returned c44 from student: Samuel Mkumbo. Condition: good', '2026-03-08 02:37:06'),
(34, 1, 'return', 'student', 246, 12, 'Returned t556 from student: Samuel Mkumbo. Condition: good', '2026-03-08 02:37:27'),
(35, 1, 'assignment', 'student', 246, 12, 'Assigned t556 (table) to student: Samuel Mkumbo', '2026-03-08 02:38:15'),
(36, 2, 'assignment', 'student', 246, 12, 'Assigned c44 (chair) to student: Samuel Mkumbo', '2026-03-08 02:38:15'),
(37, 1, 'return', 'student', 246, 12, 'Returned t556 from student: Samuel Mkumbo. Condition: good', '2026-03-08 02:38:40'),
(38, 2, 'return', 'student', 246, 12, 'Returned c44 from student: Samuel Mkumbo. Condition: good', '2026-03-08 02:38:43');

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_staff_assignments`
--

CREATE TABLE `maintenance_staff_assignments` (
  `id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL COMMENT 'Reference to admins table',
  `item_id` int(11) NOT NULL COMMENT 'Reference to maintenance_items table',
  `assignment_type` varchar(20) NOT NULL COMMENT 'Type of assignment: table, chair',
  `assigned_by` int(11) DEFAULT NULL COMMENT 'Admin who made the assignment',
  `assigned_date` date NOT NULL,
  `due_date` date DEFAULT NULL COMMENT 'Expected return date',
  `status` varchar(20) DEFAULT 'active' COMMENT 'active, returned, cancelled',
  `return_date` date DEFAULT NULL COMMENT 'Date when item was returned',
  `return_condition` varchar(20) DEFAULT NULL COMMENT 'Condition when returned: good, damaged, lost',
  `return_notes` text DEFAULT NULL COMMENT 'Notes about the return',
  `notes` text DEFAULT NULL COMMENT 'General notes about the assignment',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_staff_assignments`
--

INSERT INTO `maintenance_staff_assignments` (`id`, `staff_id`, `item_id`, `assignment_type`, `assigned_by`, `assigned_date`, `due_date`, `status`, `return_date`, `return_condition`, `return_notes`, `notes`, `created_at`, `updated_at`) VALUES
(7, 15, 5, 'table', 12, '2026-02-09', '2026-02-09', 'returned', '2026-02-09', 'good', '', '', '2026-02-09 17:54:01', '2026-02-09 17:57:33'),
(8, 15, 4, 'chair', 12, '2026-02-09', '2026-02-09', 'returned', '2026-02-09', 'good', '', '', '2026-02-09 17:54:02', '2026-02-09 17:57:35');

-- --------------------------------------------------------

--
-- Table structure for table `matches`
--

CREATE TABLE `matches` (
  `id` int(11) NOT NULL,
  `tournament_id` int(11) NOT NULL,
  `game_type_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `group_name` varchar(10) DEFAULT NULL,
  `match_number` int(11) DEFAULT NULL,
  `team1_id` int(11) NOT NULL,
  `team2_id` int(11) NOT NULL,
  `team1_score` int(11) DEFAULT 0,
  `team2_score` int(11) DEFAULT 0,
  `winner_team_id` int(11) DEFAULT NULL,
  `match_date` date NOT NULL,
  `match_time` time NOT NULL,
  `venue` varchar(100) DEFAULT NULL,
  `status` enum('Scheduled','In Progress','Completed','Postponed','Cancelled') DEFAULT 'Scheduled',
  `description` text DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `matches`
--

INSERT INTO `matches` (`id`, `tournament_id`, `game_type_id`, `stage_id`, `group_name`, `match_number`, `team1_id`, `team2_id`, `team1_score`, `team2_score`, `winner_team_id`, `match_date`, `match_time`, `venue`, `status`, `description`, `created_by`, `created_at`, `updated_at`) VALUES
(8, 4, 1, 1, 'A', NULL, 1, 8, 1, 1, NULL, '0000-00-00', '12:06:00', NULL, 'Completed', '', 32, '2026-03-31 19:06:52', '2026-03-31 19:07:06'),
(9, 4, 1, 1, 'B', NULL, 14, 10, 2, 4, 10, '0000-00-00', '22:28:00', NULL, 'Completed', '', 32, '2026-03-31 19:25:37', '2026-03-31 19:25:49'),
(10, 4, 1, 1, 'A', NULL, 5, 7, 9, 3, 5, '0000-00-00', '09:07:00', NULL, 'Completed', '', 32, '2026-04-01 06:05:44', '2026-04-01 06:06:31'),
(11, 4, 1, 2, '', NULL, 8, 6, 1, 1, NULL, '0000-00-00', '09:24:00', NULL, 'Completed', '', 32, '2026-04-01 06:22:47', '2026-04-01 12:13:38'),
(12, 4, 1, 2, '', NULL, 4, 11, 4, 5, 11, '0000-00-00', '09:00:00', NULL, 'Completed', 'goood', 32, '2026-04-01 06:58:04', '2026-04-01 09:36:51'),
(17, 4, 1, 3, NULL, NULL, 5, 1, 2, 0, 5, '2026-04-16', '08:00:00', NULL, 'Completed', NULL, 32, '2026-04-01 10:58:36', '2026-04-01 12:13:26'),
(18, 4, 1, 3, NULL, NULL, 10, 11, 3, 2, 10, '2026-04-16', '10:00:00', NULL, 'Completed', NULL, 32, '2026-04-01 10:58:36', '2026-04-01 12:13:15'),
(19, 6, 2, 1, 'A', NULL, 6, 4, 60, 73, 4, '2026-04-05', '14:00:00', '', 'Completed', '', 32, '2026-04-01 12:12:10', '2026-04-01 13:16:45'),
(26, 6, 2, 1, 'B', NULL, 1, 6, 3, 2, 1, '2026-04-13', '14:00:00', '', 'Completed', '', 32, '2026-04-01 13:41:29', '2026-04-01 13:42:02'),
(27, 6, 2, 2, 'C', NULL, 5, 16, 0, 0, NULL, '0000-00-00', '17:02:00', '', 'Scheduled', '', 32, '2026-04-01 13:47:46', '2026-04-01 13:47:46');

-- --------------------------------------------------------

--
-- Table structure for table `matches_schedule`
--

CREATE TABLE `matches_schedule` (
  `id` int(11) NOT NULL,
  `tournament_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `group_name` varchar(10) DEFAULT NULL,
  `match_number` int(11) DEFAULT NULL,
  `team1_id` int(11) NOT NULL,
  `team2_id` int(11) NOT NULL,
  `match_date` date DEFAULT NULL,
  `match_time` time DEFAULT NULL,
  `status` enum('Scheduled','Completed') DEFAULT 'Scheduled',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `match_officials`
--

CREATE TABLE `match_officials` (
  `id` int(11) NOT NULL,
  `match_id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `role` enum('Referee','Assistant Referee 1','Assistant Referee 2','Scorekeeper','Timekeeper') NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `match_statistics`
--

CREATE TABLE `match_statistics` (
  `id` int(11) NOT NULL,
  `match_id` int(11) NOT NULL,
  `team_id` int(11) NOT NULL,
  `participant_id` int(11) DEFAULT NULL,
  `participant_type` enum('Student','Staff') DEFAULT NULL,
  `event_type` enum('Goal','Yellow Card','Red Card','Substitution','Injury') NOT NULL,
  `event_time` time NOT NULL,
  `event_minute` int(11) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `notifications`
--

CREATE TABLE `notifications` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT 'Who created the notification',
  `title` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `file_path` varchar(500) DEFAULT NULL,
  `file_type` enum('image','video','audio','document','archive','other') DEFAULT NULL,
  `file_name` varchar(255) DEFAULT NULL,
  `file_size` int(11) DEFAULT NULL COMMENT 'Size in bytes',
  `visibility` enum('public','private') DEFAULT 'public',
  `priority` enum('normal','important','starred') DEFAULT 'normal',
  `status` enum('active','archived','deleted') DEFAULT 'active',
  `is_starred` tinyint(1) DEFAULT 0,
  `views_count` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `notifications`
--

INSERT INTO `notifications` (`id`, `admin_id`, `title`, `description`, `file_path`, `file_type`, `file_name`, `file_size`, `visibility`, `priority`, `status`, `is_starred`, `views_count`, `created_at`, `updated_at`) VALUES
(1, 12, 'welcome all in my views', 'nice meetings', '../uploads/notifications/695ec31b65467_muyovozi.png', 'image', '695ec31b65467_muyovozi.png', 517797, 'public', 'starred', 'active', 1, 29, '2026-01-07 14:33:31', '2026-03-11 17:42:04'),
(3, 11, 'hello', '', '../uploads/notifications/695ec94967511_Muyovozi_High_School_-_Google_Chrome_1_7_2026_1_05_52_PM.png', 'image', '695ec94967511_Muyovozi_High_School_-_Google_Chrome_1_7_2026_1_05_52_PM.png', 205346, 'private', 'normal', 'active', 0, 2, '2026-01-07 14:59:53', '2026-01-07 15:17:40'),
(8, 12, 'walimu wote tukutaane', '', '', '', '', 0, 'public', 'important', 'active', 1, 5, '2026-01-23 14:29:24', '2026-03-28 08:32:35'),
(1, 12, 'welcome all in my views', 'nice meetings', '../uploads/notifications/695ec31b65467_muyovozi.png', 'image', '695ec31b65467_muyovozi.png', 517797, 'public', 'starred', 'active', 1, 29, '2026-01-07 14:33:31', '2026-03-11 17:42:04'),
(3, 11, 'hello', '', '../uploads/notifications/695ec94967511_Muyovozi_High_School_-_Google_Chrome_1_7_2026_1_05_52_PM.png', 'image', '695ec94967511_Muyovozi_High_School_-_Google_Chrome_1_7_2026_1_05_52_PM.png', 205346, 'private', 'normal', 'active', 0, 2, '2026-01-07 14:59:53', '2026-01-07 15:17:40'),
(8, 12, 'walimu wote tukutaane', '', '', '', '', 0, 'public', 'important', 'active', 1, 5, '2026-01-23 14:29:24', '2026-03-28 08:32:35');

-- --------------------------------------------------------

--
-- Table structure for table `notification_views`
--

CREATE TABLE `notification_views` (
  `id` int(11) NOT NULL,
  `notification_id` int(11) NOT NULL,
  `viewer_id` int(11) DEFAULT NULL COMMENT 'Admin ID if logged in, NULL for guests',
  `viewer_type` enum('admin','guest') DEFAULT NULL,
  `viewed_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `notification_views`
--

INSERT INTO `notification_views` (`id`, `notification_id`, `viewer_id`, `viewer_type`, `viewed_at`) VALUES
(1, 1, 12, 'admin', '2026-01-07 14:33:56'),
(3, 1, 11, 'admin', '2026-01-07 14:55:37'),
(4, 3, 12, 'admin', '2026-01-07 15:00:40'),
(5, 3, 11, 'admin', '2026-01-07 15:17:40'),
(12, 1, 14, 'admin', '2026-01-09 11:57:23'),
(14, 8, 12, 'admin', '2026-01-26 10:00:54'),
(0, 1, 221, '', '2026-03-08 01:51:28'),
(0, 1, 221, '', '2026-03-08 01:51:28'),
(0, 8, 221, '', '2026-03-08 01:51:32'),
(0, 1, 246, '', '2026-03-08 02:04:01'),
(0, 1, 246, '', '2026-03-08 02:04:01'),
(0, 1, 246, '', '2026-03-08 02:30:38'),
(0, 1, 246, '', '2026-03-08 02:30:38'),
(0, 1, 53, '', '2026-03-08 05:39:25'),
(0, 1, 53, '', '2026-03-08 05:39:26'),
(0, 1, 53, '', '2026-03-08 05:39:33'),
(0, 1, 53, '', '2026-03-08 05:39:34'),
(0, 1, 53, '', '2026-03-08 05:39:54'),
(0, 1, 53, '', '2026-03-08 05:39:54'),
(0, 1, 251, '', '2026-03-10 13:32:11'),
(0, 1, 251, '', '2026-03-10 13:32:11'),
(0, 1, 251, '', '2026-03-10 13:32:17'),
(0, 1, 251, '', '2026-03-10 13:32:17'),
(0, 1, 251, '', '2026-03-10 13:33:12'),
(0, 1, 251, '', '2026-03-10 13:33:12'),
(0, 1, 408, '', '2026-03-10 15:46:17'),
(0, 1, 408, '', '2026-03-10 15:46:17'),
(0, 1, 408, '', '2026-03-10 15:47:42'),
(0, 1, 408, '', '2026-03-10 15:47:42'),
(0, 1, 251, '', '2026-03-11 08:57:10'),
(0, 1, 251, '', '2026-03-11 08:57:10'),
(0, 1, 251, '', '2026-03-11 17:42:04'),
(0, 1, 251, '', '2026-03-11 17:42:04'),
(0, 8, 29, 'admin', '2026-03-13 14:01:21'),
(0, 8, 14, 'admin', '2026-03-14 08:31:26'),
(0, 8, 32, 'admin', '2026-03-28 08:32:35');

-- --------------------------------------------------------

--
-- Table structure for table `password_resets`
--

CREATE TABLE `password_resets` (
  `id` int(11) NOT NULL,
  `user_type` enum('staff','student') NOT NULL,
  `user_id` int(11) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `token` varchar(100) NOT NULL,
  `otp` varchar(10) NOT NULL,
  `expires_at` datetime NOT NULL,
  `used` tinyint(4) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `password_resets`
--

INSERT INTO `password_resets` (`id`, `user_type`, `user_id`, `email`, `phone`, `token`, `otp`, `expires_at`, `used`, `created_at`) VALUES
(32, 'staff', 15, 'jen@gmail.com', '255714343162', 'e41f088ac1b4f42e9b3a514ddd90c7dc1d4cf0aa03a1bd52d33d964e7ef0e03f', '835243', '2026-03-13 13:38:37', 0, '2026-03-13 10:28:37'),
(40, 'staff', 12, 'tz@gmail.com', '255619844080', 'bdac6ae760bc56d20ca64e7f04c55668b383c38f9c9d404a26801034c7cecbe1', '277241', '2026-03-13 14:41:40', 0, '2026-03-13 11:31:40');

-- --------------------------------------------------------

--
-- Table structure for table `productions`
--

CREATE TABLE `productions` (
  `id` int(11) NOT NULL,
  `category` varchar(50) NOT NULL,
  `production_type` varchar(100) NOT NULL,
  `quantity` decimal(10,2) DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `currency` varchar(10) DEFAULT 'TZS',
  `production_date` date NOT NULL,
  `short_note` text DEFAULT NULL,
  `uses` text DEFAULT NULL,
  `created_by` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_active` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `production_categories`
--

CREATE TABLE `production_categories` (
  `id` int(11) NOT NULL,
  `category_name` varchar(50) NOT NULL,
  `description` text DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  `status` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `created_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `production_categories`
--

INSERT INTO `production_categories` (`id`, `category_name`, `description`, `unit`, `status`, `created_at`, `updated_at`, `created_by`) VALUES
(1, 'shop', 'School Shop Products', 'items', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(2, 'farm', 'Farm and Plantation Products', 'kg', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(3, 'beekeeping', 'Honey and Bee Products', 'liters', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(4, 'soap', 'Soap Making Products', 'pieces', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(5, 'fish', 'Fish Farming', 'kg', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(6, 'hen', 'Poultry and Hen Products', 'pieces', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL),
(7, 'garden', 'School Garden Products', 'kg', 1, '2026-02-09 22:03:50', '2026-02-09 22:31:40', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `production_logs`
--

CREATE TABLE `production_logs` (
  `id` int(11) NOT NULL,
  `production_id` int(11) DEFAULT NULL,
  `action` varchar(50) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `details` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `production_uses`
--

CREATE TABLE `production_uses` (
  `id` int(11) NOT NULL,
  `production_id` int(11) NOT NULL,
  `use_description` text NOT NULL,
  `use_date` date NOT NULL,
  `used_quantity` decimal(10,2) NOT NULL,
  `used_by` varchar(100) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_by` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `ps_documents`
--

CREATE TABLE `ps_documents` (
  `id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `short_note` text DEFAULT NULL,
  `file_name` varchar(255) NOT NULL,
  `file_path` varchar(500) NOT NULL,
  `file_type` enum('image','video','audio','document','spreadsheet','presentation','archive','pdf','text','other') DEFAULT 'document',
  `file_extension` varchar(20) DEFAULT NULL,
  `file_size` int(11) DEFAULT NULL COMMENT 'Size in bytes',
  `mime_type` varchar(100) DEFAULT NULL,
  `uploaded_by` int(11) NOT NULL COMMENT 'Admin ID who uploaded',
  `uploader_role` varchar(100) DEFAULT NULL,
  `uploader_name` varchar(200) DEFAULT NULL,
  `visibility` enum('public','private','staff_only') DEFAULT 'staff_only',
  `allow_feedback` tinyint(1) DEFAULT 1,
  `needs_ps_review` tinyint(1) NOT NULL DEFAULT 0,
  `ps_status` enum('pending','approved','rejected','changes_requested') DEFAULT 'approved',
  `ps_reviewed_by` int(11) DEFAULT NULL,
  `ps_reviewed_at` timestamp NULL DEFAULT NULL,
  `ps_comment` text DEFAULT NULL,
  `feedback_count` int(11) DEFAULT 0,
  `download_count` int(11) DEFAULT 0,
  `view_count` int(11) DEFAULT 0,
  `status` enum('active','archived','deleted') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `ps_document_feedback`
--

CREATE TABLE `ps_document_feedback` (
  `id` int(11) NOT NULL,
  `document_id` int(11) NOT NULL,
  `commenter_id` int(11) NOT NULL COMMENT 'Admin ID',
  `commenter_name` varchar(200) NOT NULL,
  `commenter_role` varchar(100) DEFAULT NULL,
  `comment` text NOT NULL,
  `parent_comment_id` int(11) DEFAULT NULL COMMENT 'For replies to comments',
  `status` enum('active','deleted') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `ps_document_logs`
--

CREATE TABLE `ps_document_logs` (
  `id` int(11) NOT NULL,
  `document_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `user_name` varchar(200) NOT NULL,
  `user_role` varchar(100) DEFAULT NULL,
  `action` enum('view','download','print','feedback') NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `ps_notifications`
--

CREATE TABLE `ps_notifications` (
  `id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `type` enum('ps_review','document_review','feedback','system') DEFAULT 'system',
  `user_id` int(11) DEFAULT NULL COMMENT 'Target user ID',
  `target_role` varchar(100) DEFAULT NULL COMMENT 'Target role (e.g., PS)',
  `document_id` int(11) DEFAULT NULL,
  `created_by` int(11) NOT NULL,
  `is_read` tinyint(1) DEFAULT 0,
  `status` enum('unread','read','archived') DEFAULT 'unread',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `results_auto_save`
--

CREATE TABLE `results_auto_save` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `exam_type_id` int(11) NOT NULL,
  `subject_code` varchar(20) DEFAULT NULL,
  `marks` int(11) DEFAULT NULL,
  `saved_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `session_id` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `results_entry_sessions`
--

CREATE TABLE `results_entry_sessions` (
  `id` int(11) NOT NULL,
  `exam_type_id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `started_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_activity` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_active` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `room_availability_view`
-- (See below for the actual view)
--
CREATE TABLE `room_availability_view` (
`room_id` int(11)
,`dorm_name` varchar(50)
,`dorm_type` enum('Male','Female')
,`room_number` varchar(10)
,`room_label` varchar(20)
,`capacity` int(11)
,`current_occupancy` int(11)
,`available_beds` bigint(12)
,`room_status` enum('Available','Full','Maintenance')
,`dormitory_status` enum('Active','Full','Maintenance','Closed')
,`occupancy_status` varchar(18)
,`active_students_in_room` bigint(21)
,`created_at` timestamp
,`updated_at` timestamp
);

-- --------------------------------------------------------

--
-- Table structure for table `room_status_logs`
--

CREATE TABLE `room_status_logs` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `old_status` enum('Available','Full','Maintenance') DEFAULT NULL,
  `new_status` enum('Available','Full','Maintenance') NOT NULL,
  `changed_by` int(11) DEFAULT NULL COMMENT 'Admin ID',
  `notes` text DEFAULT NULL,
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `shule_salama_comments`
--

CREATE TABLE `shule_salama_comments` (
  `id` int(11) NOT NULL,
  `post_id` int(11) NOT NULL,
  `commenter_id` int(11) NOT NULL,
  `commenter_type` enum('admin','teacher','student') NOT NULL,
  `comment` text NOT NULL,
  `status` enum('pending','approved','rejected') DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `shule_salama_comments`
--

INSERT INTO `shule_salama_comments` (`id`, `post_id`, `commenter_id`, `commenter_type`, `comment`, `status`, `created_at`) VALUES
(0, 0, 221, 'student', 'good', 'pending', '2026-03-08 01:22:57');

-- --------------------------------------------------------

--
-- Table structure for table `shule_salama_posts`
--

CREATE TABLE `shule_salama_posts` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT 'Who created the post',
  `title` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `file_path` varchar(500) DEFAULT NULL,
  `file_type` enum('image','video','audio','document','archive','other') DEFAULT NULL,
  `file_name` varchar(255) DEFAULT NULL,
  `file_size` int(11) DEFAULT NULL COMMENT 'Size in bytes',
  `visibility` enum('public','staff_only','students_only') DEFAULT 'public',
  `priority` enum('normal','important','critical','emergency') DEFAULT 'normal',
  `status` enum('active','archived','deleted') DEFAULT 'active',
  `views_count` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `shule_salama_posts`
--

INSERT INTO `shule_salama_posts` (`id`, `admin_id`, `title`, `description`, `file_path`, `file_type`, `file_name`, `file_size`, `visibility`, `priority`, `status`, `views_count`, `created_at`, `updated_at`) VALUES
(8, 12, 'hello', 'wellcome', NULL, NULL, NULL, NULL, 'public', 'normal', 'active', 0, '2026-01-23 16:29:43', '2026-01-23 16:29:43'),
(0, 12, 'tazan the greatest', 'its good for all founders', 'uploads/shule_salama/6986035d06e22_Strategic_PlaN.pdf', 'document', 'Strategic PlaN.pdf', 102202, 'public', 'normal', 'active', 0, '2026-02-06 15:06:05', '2026-02-06 15:06:05'),
(0, 12, 'helo herena', 'lle beberu bora chinja na ondoa figo nene', 'uploads/shule_salama/69860bb4974dc_muyovozi.png', 'image', 'muyovozi.png', 517797, 'staff_only', 'normal', 'active', 0, '2026-02-06 15:41:40', '2026-02-06 15:41:40'),
(0, 12, 'fdsd', 'fdsds', 'uploads/shule_salama/69860fe6d1be6_DISTRIBUTED_SYSTEM_ASSIGNMENT_3.docx', 'document', 'DISTRIBUTED SYSTEM ASSIGNMENT 3.docx', 59765, 'public', 'normal', 'active', 0, '2026-02-06 15:59:34', '2026-02-06 15:59:34'),
(0, 12, 'hello', 'its good day', NULL, NULL, NULL, NULL, 'public', 'normal', 'active', 0, '2026-03-07 21:42:29', '2026-03-07 21:42:29');

-- --------------------------------------------------------

--
-- Table structure for table `shule_salama_views`
--

CREATE TABLE `shule_salama_views` (
  `id` int(11) NOT NULL,
  `post_id` int(11) NOT NULL,
  `viewer_id` int(11) DEFAULT NULL COMMENT 'Admin ID if logged in, NULL for guests',
  `viewer_type` enum('admin','teacher','student','guest') DEFAULT NULL,
  `viewed_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `sms_logs`
--

CREATE TABLE `sms_logs` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `recipient_count` varchar(100) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `message` text NOT NULL,
  `status` varchar(20) NOT NULL,
  `response` text DEFAULT NULL,
  `sent_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `cost` decimal(10,0) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `sports_equipment`
--

CREATE TABLE `sports_equipment` (
  `id` int(11) NOT NULL,
  `item_name` varchar(100) NOT NULL,
  `category` varchar(50) NOT NULL,
  `unit` varchar(20) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 0,
  `min_quantity` int(11) NOT NULL DEFAULT 5,
  `short_note` text DEFAULT NULL,
  `image_path` varchar(255) DEFAULT NULL,
  `purchase_date` date DEFAULT NULL,
  `purchase_price` decimal(10,2) DEFAULT 0.00,
  `is_archived` tinyint(1) DEFAULT 0,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `sports_equipment`
--

INSERT INTO `sports_equipment` (`id`, `item_name`, `category`, `unit`, `quantity`, `min_quantity`, `short_note`, `image_path`, `purchase_date`, `purchase_price`, `is_archived`, `created_by`, `created_at`, `updated_at`) VALUES
(1, 'mipira', 'Football', 'ball', 6, 2, '', NULL, '2026-04-01', 0.00, 1, 32, '2026-04-01 11:33:34', '2026-04-01 11:47:41'),
(2, 'game', 'Football', 'ball', 0, 2, '', NULL, '2026-04-01', 0.00, 1, 32, '2026-04-01 11:57:33', '2026-04-01 11:58:52');

-- --------------------------------------------------------

--
-- Table structure for table `sports_history`
--

CREATE TABLE `sports_history` (
  `id` int(11) NOT NULL,
  `tournament_id` int(11) NOT NULL,
  `tournament_name` varchar(100) NOT NULL,
  `game_type_id` int(11) DEFAULT NULL,
  `season` varchar(20) DEFAULT NULL,
  `year` year(4) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `description` text DEFAULT NULL,
  `archived_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `archived_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

CREATE TABLE `students` (
  `id` int(11) NOT NULL,
  `index_number` varchar(50) DEFAULT NULL,
  `first_name` varchar(100) NOT NULL,
  `second_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `sex` enum('Male','Female') NOT NULL,
  `combination` enum('HGE','HGL','HGK','HKL','KLF','EGM','HLF','HGF') NOT NULL,
  `date_of_birth` date NOT NULL,
  `date_of_admission` date NOT NULL,
  `admission_number` varchar(50) DEFAULT NULL,
  `class` enum('Form Five','Form Six','Leavers','Graduated') NOT NULL DEFAULT 'Form Five',
  `citizenship` varchar(50) DEFAULT 'Tanzania',
  `place_of_birth` varchar(200) NOT NULL,
  `parent_name` varchar(200) NOT NULL,
  `parent_phone` varchar(20) NOT NULL,
  `password` varchar(255) NOT NULL,
  `parent_occupation` varchar(100) DEFAULT NULL,
  `parent_residence` text NOT NULL,
  `former_school` varchar(200) DEFAULT NULL,
  `school_transferred_to` varchar(200) DEFAULT NULL,
  `date_leaving_school` date DEFAULT NULL,
  `school_transferred_from` varchar(200) DEFAULT NULL,
  `status` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_leaver` tinyint(1) DEFAULT 0,
  `year_left` year(4) DEFAULT NULL,
  `previous_class` enum('Form Five','Form Six','Leavers','Graduated') DEFAULT NULL,
  `class_changed_at` timestamp NULL DEFAULT NULL,
  `is_returned` tinyint(1) DEFAULT 0,
  `graduation_status` enum('Active','Form Five','Form Six','Graduated','Left') DEFAULT 'Active',
  `graduation_year` year(4) DEFAULT NULL,
  `promotion_status` enum('Not Promoted','Promoted to Form Six','Retained') DEFAULT 'Not Promoted',
  `updated_by_admin` int(11) DEFAULT NULL,
  `failed_login_attempts` int(11) DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `last_login_attempt` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `students`
--

INSERT INTO `students` (`id`, `index_number`, `first_name`, `second_name`, `last_name`, `sex`, `combination`, `date_of_birth`, `date_of_admission`, `admission_number`, `class`, `citizenship`, `place_of_birth`, `parent_name`, `parent_phone`, `password`, `parent_occupation`, `parent_residence`, `former_school`, `school_transferred_to`, `date_leaving_school`, `school_transferred_from`, `status`, `created_at`, `updated_at`, `is_leaver`, `year_left`, `previous_class`, `class_changed_at`, `is_returned`, `graduation_status`, `graduation_year`, `promotion_status`, `updated_by_admin`, `failed_login_attempts`, `locked_until`, `last_login_attempt`) VALUES
(1, 'S5098-0523', 'TAZE', 'JUMANNE', 'TADEO', 'Male', 'HGL', '2010-02-15', '2026-01-06', '12345', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657456', '$2y$10$YourDefaultHashHere', 'MKULIMA', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-06 03:05:33', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(7, 'S5098-0563', 'jamary', 'hello', 'smith', 'Male', 'EGM', '2026-01-06', '2026-01-06', '1234678', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '0745657855', '$2y$10$YourDefaultHashHere', 'MKULIMA', 'KIGOMA', '', '', NULL, '', 1, '2026-01-06 05:17:36', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(9, 'S5098-0502', 'juju', 'juma', 'yusla', 'Female', 'HGE', '2026-01-06', '2026-01-06', '16589', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657567', '$2y$10$YourDefaultHashHere', 'MKULIMA', 'KIGOMA', '', '', NULL, '', 1, '2026-01-06 05:52:24', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(10, 'S5098-0549', 'jamary', 'JUMANNE ', 'mussa', 'Male', 'KLF', '2026-01-02', '2026-01-06', '6788', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657590', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-06 07:45:52', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(11, 'S5098-0533', 'alu', 'JUMANNE ', 'mussa', 'Female', 'HKL', '2026-01-13', '2026-01-06', '877', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657983', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-06 07:46:57', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(13, 'S5098-0514', 'halima', 'JUMANNE ', 'mussa', 'Female', 'HGL', '2025-12-30', '2026-01-06', '12345455', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657444', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-06 08:41:30', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(14, 'S5098-0524', 'aujenia', 'JUMANNE ', 'TADEO', 'Female', 'HGK', '2025-12-30', '2026-01-06', '126677', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657888', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-06 08:47:28', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(15, 'S5098-0576', 'franc', 'peter', 'leo', 'Male', 'HGF', '2020-06-06', '2026-01-06', '456782', 'Form Six', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745657765', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', 'nysrubanda', 'nyarubanda', '2026-01-06', 'muyovozi', 1, '2026-01-06 10:06:00', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(17, 'S5098-0560', 'THAZAN', 'JUMANNE ', 'TZONE', 'Male', 'HLF', '1999-02-08', '2026-01-08', '12348', 'Form Five', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255746457688', '$2y$10$YourDefaultHashHere', 'mkulima', 'KIGOMA', 'nyArubanda s1270/0114/2025', 'nyarubanda', '2026-01-08', 'muyovozi', 1, '2026-01-08 07:51:11', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(18, 'S5098-0501', 'JANETH', 'SAMSON', 'WECH', 'Female', 'HGE', '2005-07-13', '2026-01-08', '01', 'Form Six', 'Tanzania', 'KIGOMA', 'JAMARY TOPHIC', '255745657511', '$2y$10$JAImSSwHLvSjJiFkG11yyO7VUh1UaTJGdqhKl78oCX3r5RScUJ.ha', 'mkulima', 'KIGOMA', '', '', '0000-00-00', '', 1, '2026-01-08 08:07:52', '2026-03-11 09:22:26', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 2, NULL, '2026-03-11 12:22:26'),
(20, 'S5098-0507', 'Grace', 'John', 'Mkenda', 'Female', 'HGL', '2005-07-22', '2023-01-10', 'ADM002F', 'Form Five', 'Tanzania', 'Arusha', 'John Mkenda', '0755123456', '$2y$10$YourDefaultHashHere', 'Farmer', 'Arusha Municipality', 'Arusha Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(21, 'S5098-0514', 'Asha', 'Ali', 'Juma', 'Female', 'HGK', '2005-11-05', '2023-01-10', 'ADM003F', 'Form Five', 'Tanzania', 'Zanzibar', 'Ali Juma', '0777345678', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Stone Town, Zanzibar', 'Zanzibar Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(22, 'S5098-0526', 'Fatuma', 'Ramadhani', 'Hassan', 'Female', 'HKL', '2005-01-30', '2023-01-10', 'ADM004F', 'Form Five', 'Tanzania', 'Tanga', 'Ramadhani Hassan', '0765123456', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(23, 'S5098-0534', 'Aisha', 'Mohamed', 'Said', 'Female', 'KLF', '2005-09-14', '2023-01-10', 'ADM005F', 'Form Five', 'Tanzania', 'Mwanza', 'Mohamed Said', '0789345678', '$2y$10$YourDefaultHashHere', 'Doctor', 'Ilemela, Mwanza', 'Mwanza Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(24, 'S5098-0544', 'Zainab', 'Salim', 'Abdallah', 'Female', 'EGM', '2005-04-18', '2023-01-10', 'ADM006F', 'Form Five', 'Tanzania', 'Dodoma', 'Salim Abdallah', '0711123456', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(25, 'S5098-0551', 'Mariam', 'Yusuf', 'Khamis', 'Female', 'HLF', '2005-12-25', '2023-01-10', 'ADM007F', 'Form Five', 'Tanzania', 'Mbeya', 'Yusuf Khamis', '0756123456', '$2y$10$YourDefaultHashHere', 'Engineer', 'Mbeya City', 'Mbeya Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(26, 'S5098-0561', 'Happiness', 'Paul', 'Mpenda', 'Female', 'HGF', '2005-06-08', '2023-01-10', 'ADM008F', 'Form Five', 'Tanzania', 'Morogoro', 'Paul Mpenda', '0777123456', '$2y$10$YourDefaultHashHere', 'Teacher', 'Morogoro Municipality', 'Morogoro Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(27, 'S5098-0503', 'Sarah', 'David', 'Mbowe', 'Female', 'HGE', '2005-08-19', '2023-01-10', '0001', 'Form Five', 'Tanzania', 'Dar es Salaam', 'David Mbowe', '255712345679', '$2y$10$6kf4tTAXDwL2CauJTzUmiuaNrVPUKX8NbV.T8GbtoufAiXa1SfJHC', 'Businessman', 'Ilala, Dar es Salaam', 'Azania Secondary', 'muyo', '0000-00-00', '', 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, '2026-03-11 12:02:44'),
(28, 'S5098-0506', 'Catherine', 'Peter', 'Kibona', 'Female', 'HGL', '2005-02-11', '2023-01-10', 'ADM010F', 'Form Five', 'Tanzania', 'Moshi', 'Peter Kibona', '0755123457', '$2y$10$2FJu.SJ1Lpan6vx9lvN0pOsSLnlJQiWS8jbiJdYTA8olRV/Pi7dEe', 'Hotel Manager', 'Moshi Municipality', 'Moshi Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(31, 'S5098-0521', 'David', 'Jacob', 'Mwingira', 'Male', 'HGK', '2005-03-25', '2023-01-10', 'ADM013M', 'Form Five', 'Tanzania', 'Dodoma', 'Jacob Mwingira', '0777345680', '$2y$10$YourDefaultHashHere', 'Farmer', 'Dodoma Rural', 'Dodoma Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(32, 'S5098-0531', 'James', 'Thomas', 'Kapinga', 'Male', 'HKL', '2005-07-30', '2023-01-10', 'ADM014M', 'Form Five', 'Tanzania', 'Mwanza', 'Thomas Kapinga', '0765123457', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Mwanza City', 'Mwanza Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(33, 'S5098-0539', 'Peter', 'Andrew', 'Nyanda', 'Male', 'KLF', '2005-11-15', '2023-01-10', 'ADM015M', 'Form Five', 'Tanzania', 'Mbeya', 'Andrew Nyanda', '0789345680', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(34, 'S5098-0546', 'Michael', 'Christopher', 'Mpemba', 'Male', 'EGM', '2005-01-22', '2023-01-10', 'ADM016M', 'Form Five', 'Tanzania', 'Tanga', 'Christopher Mpemba', '0711123457', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(35, 'S5098-0559', 'Simon', 'Gabriel', 'Kisare', 'Male', 'HLF', '2005-09-05', '2023-01-10', 'ADM017M', 'Form Five', 'Tanzania', 'Morogoro', 'Gabriel Kisare', '0756123457', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Morogoro Municipality', 'Morogoro Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(36, 'S5098-0571', 'Paul', 'Matthew', 'Mtonga', 'Male', 'HGF', '2005-04-28', '2023-01-10', 'ADM018M', 'Form Five', 'Tanzania', 'Dar es Salaam', 'Matthew Mtonga', '0777123457', '$2y$10$YourDefaultHashHere', 'Doctor', 'Temeke, Dar es Salaam', 'Temeke Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(38, 'S5098-0511', 'Luke', 'Barnabas', 'Mosha', 'Male', 'HGL', '2005-12-10', '2023-01-10', 'ADM020M', 'Form Five', 'Tanzania', 'Moshi', 'Barnabas Mosha', '0755123459', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(39, 'S5098-0527', 'Rehema', 'Juma', 'Kondo', 'Female', 'HGK', '2004-03-15', '2022-01-10', 'ADM021F', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Juma Kondo', '0712345682', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Kinondoni, Dar es Salaam', 'Kisutu Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(40, 'S5098-0538', 'Pendo', 'Rajabu', 'Mloka', 'Female', 'HKL', '2004-07-22', '2022-01-10', 'ADM022F', 'Form Six', 'Tanzania', 'Zanzibar', 'Rajabu Mloka', '0755123460', '$2y$10$YourDefaultHashHere', 'Teacher', 'Stone Town, Zanzibar', 'Zanzibar Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(41, 'S5098-0548', 'Tumaini', 'Salum', 'Kibwana', 'Female', 'KLF', '2004-11-05', '2022-01-10', 'ADM023F', 'Form Six', 'Tanzania', 'Tanga', 'Salum Kibwana', '0777345682', '$2y$10$YourDefaultHashHere', 'Nurse', 'Tanga City', 'Tanga Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(42, 'S5098-0555', 'Furaha', 'Hamisi', 'Mwakyembe', 'Female', 'EGM', '2004-01-30', '2022-01-10', 'ADM024F', 'Form Six', 'Tanzania', 'Mwanza', 'Hamisi Mwakyembe', '0765123458', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ilemela, Mwanza', 'Mwanza Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(43, 'S5098-0568', 'Upendo', 'Issa', 'Kamala', 'Female', 'HLF', '2004-09-14', '2022-01-10', 'ADM025F', 'Form Six', 'Tanzania', 'Dodoma', 'Issa Kamala', '0789345682', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(44, 'S5098-0575', 'Imani', 'Suleiman', 'Mkumbo', 'Female', 'HGF', '2004-04-18', '2022-01-10', 'ADM026F', 'Form Six', 'Tanzania', 'Mbeya', 'Suleiman Mkumbo', '0711123458', '$2y$10$YourDefaultHashHere', 'Doctor', 'Mbeya City', 'Mbeya Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(46, 'S5098-0515', 'Mama', 'Yahya', 'Kadanya', 'Female', 'HGL', '2004-06-08', '2022-01-10', 'ADM028F', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Yahya Kadanya', '0777123458', '$2y$10$YourDefaultHashHere', 'Businessman', 'Ilala, Dar es Salaam', 'Azania Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(47, 'S5098-0525', 'Dada', 'Kassim', 'Mgeni', 'Female', 'HGK', '2004-08-19', '2022-01-10', 'ADM029F', 'Form Six', 'Tanzania', 'Arusha', 'Kassim Mgeni', '0712345683', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha Municipality', 'Arusha Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(48, 'S5098-0536', 'Mtoto', 'Hassan', 'Mwinyi', 'Female', 'HKL', '2004-02-11', '2022-01-10', 'ADM030F', 'Form Six', 'Tanzania', 'Moshi', 'Hassan Mwinyi', '0755123461', '$2y$10$YourDefaultHashHere', 'Hotel Manager', 'Moshi Municipality', 'Moshi Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(49, 'S5098-0552', 'Rajabu', 'Abdallah', 'Mfugale', 'Male', 'KLF', '2004-05-20', '2022-01-10', 'ADM031M', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Abdallah Mfugale', '0712345684', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ubungo, Dar es Salaam', 'Kisutu Boys Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(50, 'S5098-0561', 'Hamisi', 'Juma', 'Kivuyo', 'Male', 'EGM', '2004-10-12', '2022-01-10', 'ADM032M', 'Form Six', 'Tanzania', 'Arusha', 'Juma Kivuyo', '0755123462', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha City', 'Arusha Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(51, 'S5098-0570', 'Kassim', 'Salim', 'Mkwizu', 'Male', 'HLF', '2004-03-25', '2022-01-10', 'ADM033M', 'Form Six', 'Tanzania', 'Dodoma', 'Salim Mkwizu', '0777345684', '$2y$10$YourDefaultHashHere', 'Farmer', 'Dodoma Rural', 'Dodoma Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(52, 'S5098-0579', 'Suleiman', 'Omar', 'Kijaji', 'Male', 'HGF', '2004-07-30', '2022-01-10', 'ADM034M', 'Form Six', 'Tanzania', 'Mwanza', 'Omar Kijaji', '0765123459', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Mwanza City', 'Mwanza Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(53, 'S5098-0511', 'Yusuf', 'Ali', 'Mtei', 'Male', 'HGE', '2004-11-15', '2022-01-10', 'ADM035M', 'Form Six', 'Tanzania', 'Mbeya', 'Ali Mtei', '0789345684', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(54, 'S5098-0517', 'Ali', 'Mohamed', 'Mushi', 'Male', 'HGL', '2004-01-22', '2022-01-10', 'ADM036M', 'Form Six', 'Tanzania', 'Tanga', 'Mohamed Mushi', '0711123459', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(55, 'S5098-0531', 'Mohamed', 'Rashid', 'Kibwana', 'Male', 'HGK', '2004-09-05', '2022-01-10', 'ADM037M', 'Form Six', 'Tanzania', 'Morogoro', 'Rashid Kibwana', '0756123459', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Morogoro Municipality', 'Morogoro Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(56, 'S5098-0542', 'Rashid', 'Saidi', 'Mtemvu', 'Male', 'HKL', '2004-04-28', '2022-01-10', 'ADM038M', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Saidi Mtemvu', '0777123459', '$2y$10$YourDefaultHashHere', 'Doctor', 'Temeke, Dar es Salaam', 'Temeke Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(57, 'S5098-0553', 'Saidi', 'Hemed', 'Kavishe', 'Male', 'KLF', '2004-08-03', '2022-01-10', 'ADM039M', 'Form Six', 'Tanzania', 'Arusha', 'Hemed Kavishe', '0712345685', '$2y$10$YourDefaultHashHere', 'Tour Operator', 'Arusha City', 'Arusha Modern Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(58, 'S5098-0562', 'Hemed', 'Mzee', 'Mariki', 'Male', 'EGM', '2004-12-10', '2022-01-10', 'ADM040M', 'Form Six', 'Tanzania', 'Moshi', 'Mzee Mariki', '0755123463', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(59, 'S5098-0550', 'Halima', 'Seif', 'Kishimbo', 'Female', 'HLF', '2005-03-08', '2023-01-10', 'ADM041F', 'Form Five', 'Tanzania', 'Lindi', 'Seif Kishimbo', '0712345686', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Lindi Town', 'Lindi Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(60, 'S5098-0564', 'Zuhura', 'Athumani', 'Mwambene', 'Female', 'HGF', '2005-06-21', '2023-01-10', 'ADM042F', 'Form Five', 'Tanzania', 'Mtwara', 'Athumani Mwambene', '0755123464', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mtwara Mikindani', 'Mtwara Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(61, 'S5098-0506', 'Mwanahawa', 'Hassani', 'Kitwana', 'Female', 'HGE', '2005-10-04', '2023-01-10', 'ADM043F', 'Form Six', 'Tanzania', 'Pwani', 'Hassani Kitwana', '255777345686', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Kibaha', 'Pwani Girls Secondary', '', '0000-00-00', '', 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-07 14:51:41', 1, 'Form Five', NULL, 'Promoted to Form Six', 14, 0, NULL, NULL),
(62, 'S5098-0508', 'Khadija', 'Jafari', 'Mpango', 'Female', 'HGL', '2005-01-17', '2023-01-10', 'ADM044F', 'Form Five', 'Tanzania', 'Ruvuma', 'Jafari Mpango', '0765123460', '$2y$10$YourDefaultHashHere', 'Farmer', 'Songea', 'Ruvuma Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(63, 'S5098-0519', 'Sauda', 'Mwinyimkuu', 'Kibiriti', 'Female', 'HGK', '2005-07-29', '2023-01-10', 'ADM045F', 'Form Five', 'Tanzania', 'Shinyanga', 'Mwinyimkuu Kibiriti', '0789345686', '$2y$10$YourDefaultHashHere', 'Miner', 'Shinyanga Town', 'Shinyanga Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(64, 'S5098-0528', 'Bakari', 'Mwinyi', 'Mwandu', 'Male', 'HKL', '2005-04-12', '2023-01-10', 'ADM046M', 'Form Five', 'Tanzania', 'Kagera', 'Mwinyi Mwandu', '0711123460', '$2y$10$YourDefaultHashHere', 'Businessman', 'Bukoba', 'Kagera Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(65, 'S5098-0551', 'Juma', 'Makame', 'Kisanga', 'Male', 'KLF', '2005-09-24', '2023-01-10', 'ADM047M', 'Form Six', 'Tanzania', 'Mara', 'Makame Kisanga', '0756123460', '$2y$10$YourDefaultHashHere', 'Teacher', 'Musoma', 'Mara Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(66, 'S5098-0547', 'Ramadhani', 'Mzee', 'Kibanda', 'Male', 'EGM', '2005-12-07', '2023-01-10', 'ADM048M', 'Form Five', 'Tanzania', 'Manyara', 'Mzee Kibanda', '0777123460', '$2y$10$YourDefaultHashHere', 'Farmer', 'Babati', 'Manyara Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(67, 'S5098-0556', 'Mwinyi', 'Kondo', 'Msangi', 'Male', 'HLF', '2005-05-19', '2023-01-10', 'ADM049M', 'Form Five', 'Tanzania', 'Geita', 'Kondo Msangi', '0712345687', '$2y$10$YourDefaultHashHere', 'Miner', 'Geita Town', 'Geita Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(68, 'S5098-0568', 'Makame', 'Hussein', 'Kijiko', 'Male', 'HGF', '2005-08-01', '2023-01-10', 'ADM050M', 'Form Five', 'Tanzania', 'Simiyu', 'Hussein Kijiko', '0755123465', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Bariadi', 'Simiyu Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(69, 'S5098-0504', 'Maimuna', 'Khamis', 'Mkubwa', 'Female', 'HGE', '2004-02-14', '2022-01-10', 'ADM051F', 'Form Six', 'Tanzania', 'Katavi', 'Khamis Mkubwa', '0777345687', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Mpanda', 'Katavi Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(70, 'S5098-0516', 'Mwanajuma', 'Sadiki', 'Kibao', 'Female', 'HGL', '2004-05-27', '2022-01-10', 'ADM052F', 'Form Six', 'Tanzania', 'Njombe', 'Sadiki Kibao', '0765123461', '$2y$10$YourDefaultHashHere', 'Teacher', 'Njombe Town', 'Njombe Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(71, 'S5098-0528', 'Tabu', 'Mzee', 'Kikwete', 'Female', 'HGK', '2004-09-09', '2022-01-10', 'ADM053F', 'Form Six', 'Tanzania', 'Kigoma', 'Mzee Kikwete', '0789345687', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Kigoma Ujiji', 'Kigoma Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(72, 'S5098-0537', 'Mwajuma', 'Hamad', 'Kibona', 'Female', 'HKL', '2004-12-22', '2022-01-10', 'ADM054F', 'Form Six', 'Tanzania', 'Rukwa', 'Hamad Kibona', '0711123461', '$2y$10$YourDefaultHashHere', 'Farmer', 'Sumbawanga', 'Rukwa Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(73, 'S5098-0545', 'Jamila', 'Abdul', 'Mteule', 'Female', 'KLF', '2004-03-06', '2022-01-10', 'ADM055F', 'Form Six', 'Tanzania', 'Pemba', 'Abdul Mteule', '0756123461', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Chake Chake', 'Pemba Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(74, 'S5098-0558', 'Abdallah', 'Kombo', 'Mpemba', 'Male', 'EGM', '2004-06-19', '2022-01-10', 'ADM056M', 'Form Six', 'Tanzania', 'Unguja', 'Kombo Mpemba', '0777123461', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Zanzibar Town', 'Unguja Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(75, 'S5098-0571', 'Kombo', 'Kondo', 'Kiwia', 'Male', 'HLF', '2004-10-02', '2022-01-10', 'ADM057M', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Kondo Kiwia', '0712345688', '$2y$10$YourDefaultHashHere', 'Engineer', 'Kigamboni, Dar es Salaam', 'Kigamboni Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(76, 'S5098-0578', 'Kondo', 'Mzee', 'Kilonzo', 'Male', 'HGF', '2004-01-15', '2022-01-10', 'ADM058M', 'Form Six', 'Tanzania', 'Arusha', 'Mzee Kilonzo', '0755123466', '$2y$10$YourDefaultHashHere', 'Tour Operator', 'Arusha City', 'Arusha Technical Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(78, 'S5098-0522', 'Massawe', 'Chamwela', 'Kimario', 'Male', 'HGL', '2004-08-11', '2022-01-10', 'ADM060M', 'Form Six', 'Tanzania', 'Dodoma', 'Chamwela Kimario', '0765123462', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Technical Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(79, 'S5098-0516', 'Ester', 'Daudi', 'Minja', 'Female', 'HGK', '2005-11-24', '2023-01-10', 'ADM061F', 'Form Five', 'Tanzania', 'Mbeya', 'Daudi Minja', '0789345688', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Technical Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(81, 'S5098-0537', 'Ruth', 'Yuda', 'Mwalukasa', 'Female', 'KLF', '2005-06-20', '2023-01-10', 'ADM063F', 'Form Five', 'Tanzania', 'Morogoro', 'Yuda Mwalukasa', '0756123462', '$2y$10$YourDefaultHashHere', 'Doctor', 'Morogoro Municipality', 'Morogoro Technical Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(82, 'S5098-0542', 'Naomi', 'Naftali', 'Mwakalinga', 'Female', 'EGM', '2005-10-03', '2023-01-10', 'ADM064F', 'Form Five', 'Tanzania', 'Mwanza', 'Naftali Mwakalinga', '0777123462', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ilemela, Mwanza', 'Mwanza Technical Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(83, 'S5098-0552', 'Rachel', 'Joshua', 'Mtepa', 'Female', 'HLF', '2005-01-16', '2023-01-10', 'ADM065F', 'Form Five', 'Tanzania', 'Arusha', 'Joshua Mtepa', '0712345689', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha City', 'Arusha Technical Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(84, 'S5098-0565', 'Elia', 'Samson', 'Mkumbo', 'Male', 'HGF', '2005-04-29', '2023-01-10', 'ADM066M', 'Form Five', 'Tanzania', 'Moshi', 'Samson Mkumbo', '0755123467', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Technical Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(85, 'S5098-0510', 'Samson', 'Daniel', 'Mlinga', 'Male', 'HGE', '2005-08-12', '2023-01-10', 'ADM067M', 'Form Six', 'Tanzania', 'Kinondoni, Dar es Salaam', 'Daniel Mlinga', '0777345689', '$2y$10$YourDefaultHashHere', 'Businessman', 'Kinondoni, Dar es Salaam', 'Kinondoni Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(87, 'S5098-0523', 'Nathan', 'Isaac', 'Mkama', 'Male', 'HGK', '2005-03-09', '2023-01-10', 'ADM069M', 'Form Five', 'Tanzania', 'Tanga', 'Isaac Mkama', '0789345689', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tanga City', 'Tanga Technical Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(88, 'S5098-0530', 'Isaac', 'Abraham', 'Mkwawa', 'Male', 'HKL', '2005-06-22', '2023-01-10', 'ADM070M', 'Form Five', 'Tanzania', 'Iringa', 'Abraham Mkwawa', '0711123463', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Iringa Municipality', 'Iringa Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(89, 'S5098-0546', 'Lydia', 'Zakaria', 'Mabula', 'Female', 'KLF', '2004-10-05', '2022-01-10', 'ADM071F', 'Form Six', 'Tanzania', 'Songwe', 'Zakaria Mabula', '0756123463', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Vwawa', 'Songwe Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(90, 'S5098-0556', 'Miriam', 'Hosea', 'Mgimwa', 'Female', 'EGM', '2004-01-18', '2022-01-10', 'ADM072F', 'Form Six', 'Tanzania', 'Tabora', 'Hosea Mgimwa', '0777123463', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tabora Municipality', 'Tabora Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(91, 'S5098-0566', 'Hannah', 'Amos', 'Mwakalukwa', 'Female', 'HLF', '2004-05-01', '2022-01-10', 'ADM073F', 'Form Six', 'Tanzania', 'Singida', 'Amos Mwakalukwa', '0712345690', '$2y$10$YourDefaultHashHere', 'Nurse', 'Singida Town', 'Singida Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(92, 'S5098-0573', 'Elizabeth', 'Jeremiah', 'Mfupi', 'Female', 'HGF', '2004-08-14', '2022-01-10', 'ADM074F', 'Form Six', 'Tanzania', 'Mara', 'Jeremiah Mfupi', '0755123468', '$2y$10$YourDefaultHashHere', 'Doctor', 'Musoma', 'Mara Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(93, 'S5098-0505', 'Mary', 'Ezekiel', 'Mkumbo', 'Female', 'HGE', '2004-11-27', '2022-01-10', 'ADM075F', 'Form Six', 'Tanzania', 'Kagera', 'Ezekiel Mkumbo', '0777345690', '$2y$10$YourDefaultHashHere', 'Engineer', 'Bukoba', 'Kagera Girls Secondary', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(94, 'S5098-0521', 'Ezekiel', 'Isaiah', 'Mnyampala', 'Male', 'HGL', '2004-03-11', '2022-01-10', 'ADM076M', 'Form Six', 'Tanzania', 'Shinyanga', 'Isaiah Mnyampala', '0765123464', '$2y$10$YourDefaultHashHere', 'Miner', 'Shinyanga Town', 'Shinyanga Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(95, 'S5098-0530', 'Isaiah', 'Malachi', 'Mwakipesile', 'Male', 'HGK', '2004-06-24', '2022-01-10', 'ADM077M', 'Form Six', 'Tanzania', 'Geita', 'Malachi Mwakipesile', '0789345690', '$2y$10$YourDefaultHashHere', 'Miner', 'Geita Town', 'Geita Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(96, 'S5098-0541', 'Malachi', 'Jonah', 'Mwagike', 'Male', 'HKL', '2004-10-07', '2022-01-10', 'ADM078M', 'Form Six', 'Tanzania', 'Simiyu', 'Jonah Mwagike', '0711123464', '$2y$10$YourDefaultHashHere', 'Farmer', 'Bariadi', 'Simiyu Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(97, 'S5098-0550', 'Jonah', 'Obadiah', 'Mkude', 'Male', 'KLF', '2004-01-20', '2022-01-10', 'ADM079M', 'Form Six', 'Tanzania', 'Katavi', 'Obadiah Mkude', '0756123464', '$2y$10$YourDefaultHashHere', 'Businessman', 'Mpanda', 'Katavi Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(98, 'S5098-0564', 'Obadiah', 'Micah', 'Mwalongo', 'Male', 'EGM', '2004-05-03', '2022-01-10', 'ADM080M', 'Form Six', 'Tanzania', 'Njombe', 'Micah Mwalongo', '0777123464', '$2y$10$YourDefaultHashHere', 'Teacher', 'Njombe Town', 'Njombe Technical', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(179, 'S5098-0553', 'Rose', 'Moses', 'Mwandosya', 'Female', 'HLF', '2005-09-16', '2023-01-10', 'ADM081F', 'Form Five', 'Tanzania', 'Kigoma', 'Moses Mwandosya', '0712345691', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Kigoma Ujiji', 'Kigoma Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(180, 'S5098-0562', 'Joyce', 'Aaron', 'Mkenda', 'Female', 'HGF', '2005-12-29', '2023-01-10', 'ADM082F', 'Form Five', 'Tanzania', 'Rukwa', 'Aaron Mkenda', '0755123469', '$2y$10$YourDefaultHashHere', 'Farmer', 'Sumbawanga', 'Rukwa Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(182, 'S5098-0510', 'Teresia', 'Joshua', 'Mwangoka', 'Female', 'HGL', '2005-07-24', '2023-01-10', 'ADM084F', 'Form Five', 'Tanzania', 'Unguja', 'Joshua Mwangoka', '0765123465', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Zanzibar Town', 'Unguja Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(183, 'S5098-0515', 'Consolata', 'Benjamin', 'Mkude', 'Female', 'HGK', '2005-11-06', '2023-01-10', 'ADM085F', 'Form Five', 'Tanzania', 'Dar es Salaam', 'Benjamin Mkude', '0789345691', '$2y$10$YourDefaultHashHere', 'Engineer', 'Kigamboni', 'Kigamboni Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(184, 'S5098-0540', 'Benjamin', 'Samuel', 'Mwangosi', 'Male', 'HKL', '2005-02-19', '2023-01-10', 'ADM086M', 'Form Six', 'Tanzania', 'Arusha', 'Samuel Mwangosi', '255711123465', '$2y$10$YourDefaultHashHere', 'Tour Operator', 'Arusha City', 'Arusha Boys', '', '0000-00-00', '', 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(185, 'S5098-0540', 'Samuel', 'Solomon', 'Mkuchika', 'Male', 'KLF', '2005-06-02', '2023-01-10', 'ADM087M', 'Form Five', 'Tanzania', 'Moshi', 'Solomon Mkuchika', '0756123465', '$2y$10$YourDefaultHashHere', 'Hotel Manager', 'Moshi Rural', 'Moshi Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(186, 'S5098-0548', 'Solomon', 'Reuben', 'Mwaibula', 'Male', 'EGM', '2005-09-15', '2023-01-10', 'ADM088M', 'Form Five', 'Tanzania', 'Dodoma', 'Reuben Mwaibula', '0777123465', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(187, 'S5098-0557', 'Reuben', 'Levi', 'Mwinuka', 'Male', 'HLF', '2005-12-28', '2023-01-10', 'ADM089M', 'Form Five', 'Tanzania', 'Mbeya', 'Levi Mwinuka', '0712345692', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(188, 'S5098-0567', 'Levi', 'Judah', 'Mwakapalala', 'Male', 'HGF', '2005-04-10', '2023-01-10', 'ADM090M', 'Form Five', 'Tanzania', 'Tanga', 'Judah Mwakapalala', '0755123470', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(189, 'S5098-0503', 'Magdalena', 'Simeon', 'Mteule', 'Female', 'HGE', '2004-07-23', '2022-01-10', 'ADM091F', 'Form Six', 'Tanzania', 'Morogoro', 'Simeon Mteule', '0777345692', '$2y$10$YourDefaultHashHere', 'Doctor', 'Morogoro Municipality', 'Morogoro Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(190, 'S5098-0512', 'Agnes', 'Gad', 'Mkumbo', 'Female', 'HGL', '2004-11-05', '2022-01-10', 'ADM092F', 'Form Six', 'Tanzania', 'Mwanza', 'Gad Mkumbo', '0765123466', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ilemela, Mwanza', 'Mwanza Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(191, 'S5098-0529', 'Veronica', 'Asher', 'Mwagikana', 'Female', 'HGK', '2004-02-18', '2022-01-10', 'ADM093F', 'Form Six', 'Tanzania', 'Arusha', 'Asher Mwagikana', '0789345692', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha City', 'Arusha Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(192, 'S5098-0534', 'Christina', 'Naphtali', 'Mkumbo', 'Female', 'HKL', '2004-06-01', '2022-01-10', 'ADM094F', 'Form Six', 'Tanzania', 'Moshi', 'Naphtali Mkumbo', '0711123466', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(193, 'S5098-0547', 'Monica', 'Joseph', 'Mwakalukwa', 'Female', 'KLF', '2004-09-14', '2022-01-10', 'ADM095F', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Joseph Mwakalukwa', '0756123466', '$2y$10$YourDefaultHashHere', 'Businessman', 'Kinondoni', 'Kinondoni Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(194, 'S5098-0560', 'Gideon', 'Dan', 'Mkumbo', 'Male', 'EGM', '2004-12-27', '2022-01-10', 'ADM096M', 'Form Six', 'Tanzania', 'Zanzibar', 'Dan Mkumbo', '0777123466', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Stone Town', 'Zanzibar Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(195, 'S5098-0569', 'Dan', 'Zebulun', 'Mtepa', 'Male', 'HLF', '2004-04-09', '2022-01-10', 'ADM097M', 'Form Six', 'Tanzania', 'Tanga', 'Zebulun Mtepa', '0712345693', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tanga City', 'Tanga Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(196, 'S5098-0580', 'Zebulun', 'Issachar', 'Mwangoka', 'Male', 'HGF', '2004-07-22', '2022-01-10', 'ADM098M', 'Form Six', 'Tanzania', 'Iringa', 'Issachar Mwangoka', '0755123471', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Iringa Municipality', 'Iringa Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(197, 'S5098-0508', 'Issachar', 'Benjamin', 'Mkinda', 'Male', 'HGE', '2004-11-04', '2022-01-10', 'ADM099M', 'Form Six', 'Tanzania', 'Songwe', 'Benjamin Mkinda', '0777345693', '$2y$10$YourDefaultHashHere', 'Businessman', 'Vwawa', 'Songwe Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, NULL, '2026-02-06 12:40:23', 1, 'Form Six', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(198, 'S5098-0520', 'Ephraim', 'Manasseh', 'Mwakasaka', 'Male', 'HGL', '2004-02-17', '2022-01-10', 'ADM100M', 'Form Six', 'Tanzania', 'Tabora', 'Manasseh Mwakasaka', '0765123467', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tabora Municipality', 'Tabora Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(199, 'S5098-0517', 'Patricia', 'Ephraim', 'Mngumi', 'Female', 'HGK', '2005-05-31', '2023-01-10', 'ADM101F', 'Form Five', 'Tanzania', 'Singida', 'Ephraim Mngumi', '0789345693', '$2y$10$YourDefaultHashHere', 'Nurse', 'Singida Town', 'Singida Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(200, 'S5098-0525', 'Eunice', 'Manasseh', 'Mkumbo', 'Female', 'HKL', '2005-09-13', '2023-01-10', 'ADM102F', 'Form Five', 'Tanzania', 'Mara', 'Manasseh Mkumbo', '0711123467', '$2y$10$YourDefaultHashHere', 'Doctor', 'Musoma', 'Mara Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(201, 'S5098-0535', 'Beatrice', 'Reuben', 'Mwanga', 'Female', 'KLF', '2005-12-26', '2023-01-10', 'ADM103F', 'Form Five', 'Tanzania', 'Kagera', 'Reuben Mwanga', '0756123467', '$2y$10$YourDefaultHashHere', 'Engineer', 'Bukoba', 'Kagera Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(202, 'S5098-0541', 'Leticia', 'Simeon', 'Mtepa', 'Female', 'EGM', '2005-04-08', '2023-01-10', 'ADM104F', 'Form Five', 'Tanzania', 'Shinyanga', 'Simeon Mtepa', '0777123467', '$2y$10$YourDefaultHashHere', 'Miner', 'Shinyanga Town', 'Shinyanga Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(203, 'S5098-0555', 'Victoria', 'Levi', 'Mwakalinga', 'Female', 'HLF', '2005-07-21', '2023-01-10', 'ADM105F', 'Form Five', 'Tanzania', 'Geita', 'Levi Mwakalinga', '0712345694', '$2y$10$YourDefaultHashHere', 'Miner', 'Geita Town', 'Geita Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(204, 'S5098-0569', 'Manasseh', 'Judah', 'Mwakalukwa', 'Male', 'HGF', '2005-11-03', '2023-01-10', 'ADM106M', 'Form Five', 'Tanzania', 'Simiyu', 'Judah Mwakalukwa', '0755123472', '$2y$10$YourDefaultHashHere', 'Farmer', 'Bariadi', 'Simiyu Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(205, 'S5098-0509', 'Judah', 'Zebulun', 'Mwagike', 'Male', 'HGE', '2005-02-16', '2023-01-10', 'ADM107M', 'Form Six', 'Tanzania', 'Katavi', 'Zebulun Mwagike', '0777345694', '$2y$10$YourDefaultHashHere', 'Businessman', 'Mpanda', 'Katavi Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(206, 'S5098-0513', 'Zebulun', 'Issachar', 'Mkude', 'Male', 'HGL', '2005-05-30', '2023-01-10', 'ADM108M', 'Form Five', 'Tanzania', 'Njombe', 'Issachar Mkude', '0765123468', '$2y$10$YourDefaultHashHere', 'Teacher', 'Njombe Town', 'Njombe Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(207, 'S5098-0522', 'Issachar', 'Gad', 'Mwalongo', 'Male', 'HGK', '2005-09-12', '2023-01-10', 'ADM109M', 'Form Five', 'Tanzania', 'Kigoma', 'Gad Mwalongo', '0789345694', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Kigoma Ujiji', 'Kigoma Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(208, 'S5098-0529', 'Gad', 'Asher', 'Mwandosya', 'Male', 'HKL', '2005-12-25', '2023-01-10', 'ADM110M', 'Form Five', 'Tanzania', 'Rukwa', 'Asher Mwandosya', '0711123468', '$2y$10$YourDefaultHashHere', 'Farmer', 'Sumbawanga', 'Rukwa Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(209, 'S5098-0544', 'Jackline', 'Dan', 'Mtega', 'Female', 'KLF', '2004-04-07', '2022-01-10', 'ADM111F', 'Form Six', 'Tanzania', 'Pemba', 'Dan Mtega', '0756123468', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Chake Chake', 'Pemba Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(210, 'S5098-0557', 'Vivian', 'Naphtali', 'Mwangoka', 'Female', 'EGM', '2004-07-20', '2022-01-10', 'ADM112F', 'Form Six', 'Tanzania', 'Unguja', 'Naphtali Mwangoka', '0777123468', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Zanzibar Town', 'Unguja Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(211, 'S5098-0567', 'Sylvia', 'Benjamin', 'Mkude', 'Female', 'HLF', '2004-11-02', '2022-01-10', 'ADM113F', 'Form Six', 'Tanzania', 'Dar es Salaam', 'Benjamin Mkude', '0712345695', '$2y$10$YourDefaultHashHere', 'Engineer', 'Kigamboni', 'Kigamboni Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(212, 'S5098-0574', 'Gloria', 'Samuel', 'Mwangosi', 'Female', 'HGF', '2004-02-15', '2022-01-10', 'ADM114F', 'Form Six', 'Tanzania', 'Arusha', 'Samuel Mwangosi', '0755123473', '$2y$10$YourDefaultHashHere', 'Tour Operator', 'Arusha City', 'Arusha Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(213, 'S5098-0501', 'Diana', 'Solomon', 'Mkuchika', 'Female', 'HGE', '2004-05-29', '2022-01-10', 'ADM115F', 'Leavers', 'Tanzania', 'Moshi', 'Solomon Mkuchika', '0777345695', '$2y$10$YourDefaultHashHere', 'Hotel Manager', 'Moshi Rural', 'Moshi Girls', NULL, NULL, NULL, 0, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 1, '2026', 'Form Five', NULL, 1, 'Left', '2026', 'Retained', 12, 0, NULL, NULL),
(214, 'S5098-0518', 'Asher', 'Reuben', 'Mwaibula', 'Male', 'HGL', '2004-09-11', '2022-01-10', 'ADM116M', 'Form Six', 'Tanzania', 'Dodoma', 'Reuben Mwaibula', '0765123469', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL);
INSERT INTO `students` (`id`, `index_number`, `first_name`, `second_name`, `last_name`, `sex`, `combination`, `date_of_birth`, `date_of_admission`, `admission_number`, `class`, `citizenship`, `place_of_birth`, `parent_name`, `parent_phone`, `password`, `parent_occupation`, `parent_residence`, `former_school`, `school_transferred_to`, `date_leaving_school`, `school_transferred_from`, `status`, `created_at`, `updated_at`, `is_leaver`, `year_left`, `previous_class`, `class_changed_at`, `is_returned`, `graduation_status`, `graduation_year`, `promotion_status`, `updated_by_admin`, `failed_login_attempts`, `locked_until`, `last_login_attempt`) VALUES
(215, 'S5098-0532', 'Naphtali', 'Levi', 'Mwinuka', 'Male', 'HGK', '2004-12-24', '2022-01-10', 'ADM117M', 'Form Six', 'Tanzania', 'Mbeya', 'Levi Mwinuka', '0789345695', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(216, 'S5098-0539', 'Benjamin', 'Judah', 'Mwakapalala', 'Male', 'HKL', '2004-04-06', '2022-01-10', 'ADM118M', 'Form Six', 'Tanzania', 'Tanga', 'Judah Mwakapalala', '0711123469', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(217, 'S5098-0554', 'Samuel', 'Simeon', 'Mteule', 'Male', 'KLF', '2004-07-19', '2022-01-10', 'ADM119M', 'Form Six', 'Tanzania', 'Morogoro', 'Simeon Mteule', '0756123469', '$2y$10$YourDefaultHashHere', 'Doctor', 'Morogoro Municipality', 'Morogoro Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(218, 'S5098-0565', 'Solomon', 'Gad', 'Mkumbo', 'Male', 'EGM', '2004-11-01', '2022-01-10', 'ADM120M', 'Form Six', 'Tanzania', 'Mwanza', 'Gad Mkumbo', '0777123469', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ilemela, Mwanza', 'Mwanza Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(219, 'S5098-0549', 'Flora', 'Asher', 'Mwagikana', 'Female', 'HLF', '2005-02-14', '2023-01-10', 'ADM121F', 'Form Five', 'Tanzania', 'Arusha', 'Asher Mwagikana', '0712345696', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha City', 'Arusha Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(220, 'S5098-0563', 'Linda', 'Naphtali', 'Mkumbo', 'Female', 'HGF', '2005-05-28', '2023-01-10', 'ADM122F', 'Form Five', 'Tanzania', 'Moshi', 'Naphtali Mkumbo', '0755123474', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(221, 'S5098-0504', 'Tatu', 'Joseph', 'Mwakalukwa', 'Female', 'HGE', '2005-09-10', '2023-01-10', 'ADM123F', 'Form Five', 'Tanzania', 'Dar es Salaam', 'Joseph Mwakalukwa', '0777345696', '$2y$10$YourDefaultHashHere', 'Businessman', 'Kinondoni', 'Kinondoni Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(222, 'S5098-0509', 'Mwajuma', 'Dan', 'Mkumbo', 'Female', 'HGL', '2005-12-23', '2023-01-10', 'ADM124F', 'Form Five', 'Tanzania', 'Zanzibar', 'Dan Mkumbo', '0765123470', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Stone Town', 'Zanzibar Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(223, 'S5098-0520', 'Zawadi', 'Zebulun', 'Mtepa', 'Female', 'HGK', '2005-04-05', '2023-01-10', 'ADM125F', 'Form Five', 'Tanzania', 'Tanga', 'Zebulun Mtepa', '0789345696', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tanga City', 'Tanga Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(224, 'S5098-0533', 'Reuben', 'Issachar', 'Mwangoka', 'Male', 'HKL', '2005-07-18', '2023-01-10', 'ADM126M', 'Form Five', 'Tanzania', 'Iringa', 'Issachar Mwangoka', '0711123470', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Iringa Municipality', 'Iringa Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(225, 'S5098-0538', 'Levi', 'Benjamin', 'Mkinda', 'Male', 'KLF', '2005-10-31', '2023-01-10', 'ADM127M', 'Form Five', 'Tanzania', 'Songwe', 'Benjamin Mkinda', '0756123470', '$2y$10$YourDefaultHashHere', 'Businessman', 'Vwawa', 'Songwe Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(226, 'S5098-0545', 'Judah', 'Manasseh', 'Mwakasaka', 'Male', 'EGM', '2005-02-13', '2023-01-10', 'ADM128M', 'Form Five', 'Tanzania', 'Tabora', 'Manasseh Mwakasaka', '0777123470', '$2y$10$YourDefaultHashHere', 'Teacher', 'Tabora Municipality', 'Tabora Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(227, 'S5098-0558', 'Simeon', 'Ephraim', 'Mngumi', 'Male', 'HLF', '2005-05-27', '2023-01-10', 'ADM129M', 'Form Five', 'Tanzania', 'Singida', 'Ephraim Mngumi', '0712345697', '$2y$10$YourDefaultHashHere', 'Nurse', 'Singida Town', 'Singida Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(228, 'S5098-0566', 'Gad', 'Manasseh', 'Mkumbo', 'Male', 'HGF', '2005-09-09', '2023-01-10', 'ADM130M', 'Form Five', 'Tanzania', 'Mara', 'Manasseh Mkumbo', '0755123475', '$2y$10$YourDefaultHashHere', 'Doctor', 'Musoma', 'Mara Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(229, 'S5098-0507', 'Stella', 'Reuben', 'Mwanga', 'Female', 'HGE', '2004-12-22', '2022-01-10', 'ADM131F', 'Form Six', 'Tanzania', 'Kagera', 'Reuben Mwanga', '0777345697', '$2y$10$YourDefaultHashHere', 'Engineer', 'Bukoba', 'Kagera Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(230, 'S5098-0513', 'Anita', 'Simeon', 'Mtepa', 'Female', 'HGL', '2004-04-04', '2022-01-10', 'ADM132F', 'Form Six', 'Tanzania', 'Shinyanga', 'Simeon Mtepa', '0765123471', '$2y$10$YourDefaultHashHere', 'Miner', 'Shinyanga Town', 'Shinyanga Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(231, 'S5098-0526', 'Judith', 'Levi', 'Mwakalinga', 'Female', 'HGK', '2004-07-17', '2022-01-10', 'ADM133F', 'Form Six', 'Tanzania', 'Geita', 'Levi Mwakalinga', '0789345697', '$2y$10$YourDefaultHashHere', 'Miner', 'Geita Town', 'Geita Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(232, 'S5098-0535', 'Martha', 'Judah', 'Mwakalukwa', 'Female', 'HKL', '2004-10-30', '2022-01-10', 'ADM134F', 'Form Six', 'Tanzania', 'Simiyu', 'Judah Mwakalukwa', '0711123471', '$2y$10$YourDefaultHashHere', 'Farmer', 'Bariadi', 'Simiyu Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(233, 'S5098-0543', 'Esther', 'Zebulun', 'Mwagike', 'Female', 'KLF', '2004-02-12', '2022-01-10', 'ADM135F', 'Form Six', 'Tanzania', 'Katavi', 'Zebulun Mwagike', '0756123471', '$2y$10$YourDefaultHashHere', 'Businesswoman', 'Mpanda', 'Katavi Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(234, 'S5098-0559', 'Dan', 'Issachar', 'Mkude', 'Male', 'EGM', '2004-05-26', '2022-01-10', 'ADM136M', 'Form Six', 'Tanzania', 'Njombe', 'Issachar Mkude', '0777123471', '$2y$10$YourDefaultHashHere', 'Teacher', 'Njombe Town', 'Njombe Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(235, 'S5098-0572', 'Zebulun', 'Gad', 'Mwalongo', 'Male', 'HLF', '2004-09-08', '2022-01-10', 'ADM137M', 'Form Six', 'Tanzania', 'Kigoma', 'Gad Mwalongo', '0712345698', '$2y$10$YourDefaultHashHere', 'Fisherman', 'Kigoma Ujiji', 'Kigoma Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(236, 'S5098-0577', 'Issachar', 'Asher', 'Mwandosya', 'Male', 'HGF', '2004-12-21', '2022-01-10', 'ADM138M', 'Form Six', 'Tanzania', 'Rukwa', 'Asher Mwandosya', '0755123476', '$2y$10$YourDefaultHashHere', 'Farmer', 'Sumbawanga', 'Rukwa Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(237, 'S5098-0501', 'Gad', 'Dan', 'Mtega', 'Male', 'HGE', '2004-04-03', '2022-01-10', 'ADM139M', 'Leavers', 'Tanzania', 'Pemba', 'Dan Mtega', '0765123472', '$2y$10$YourDefaultHashHere', 'Businessman', 'Chake Chake', 'Pemba Boys', NULL, NULL, NULL, 0, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 1, '2026', 'Form Six', '2026-02-06 12:40:23', 1, 'Graduated', '2026', 'Promoted to Form Six', 12, 0, NULL, NULL),
(238, 'S5098-0519', 'Asher', 'Naphtali', 'Mwangoka', 'Male', 'HGL', '2004-07-16', '2022-01-10', 'ADM140M', 'Form Six', 'Tanzania', 'Unguja', 'Naphtali Mwangoka', '0789345698', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Zanzibar Town', 'Unguja Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-10 14:44:55', 0, NULL, 'Form Five', '2026-02-06 12:40:23', 1, 'Form Five', NULL, 'Promoted to Form Six', 12, 0, NULL, NULL),
(239, 'S5098-0518', 'Paulina', 'Benjamin', 'Mkude', 'Female', 'HGK', '2005-10-29', '2023-01-10', 'ADM141F', 'Form Five', 'Tanzania', 'Dar es Salaam', 'Benjamin Mkude', '0711123472', '$2y$10$YourDefaultHashHere', 'Engineer', 'Kigamboni', 'Kigamboni Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(240, 'S5098-0527', 'Salome', 'Samuel', 'Mwangosi', 'Female', 'HKL', '2005-02-11', '2023-01-10', 'ADM142F', 'Form Five', 'Tanzania', 'Arusha', 'Samuel Mwangosi', '0756123472', '$2y$10$YourDefaultHashHere', 'Tour Operator', 'Arusha City', 'Arusha Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(241, 'S5098-0536', 'Rehema', 'Solomon', 'Mkuchika', 'Female', 'KLF', '2005-05-25', '2023-01-10', 'ADM143F', 'Form Five', 'Tanzania', 'Moshi', 'Solomon Mkuchika', '0777123472', '$2y$10$YourDefaultHashHere', 'Hotel Manager', 'Moshi Rural', 'Moshi Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(242, 'S5098-0543', 'Pili', 'Reuben', 'Mwaibula', 'Female', 'EGM', '2005-09-07', '2023-01-10', 'ADM144F', 'Form Five', 'Tanzania', 'Dodoma', 'Reuben Mwaibula', '0712345699', '$2y$10$YourDefaultHashHere', 'Civil Servant', 'Dodoma City', 'Dodoma Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(243, 'S5098-0554', 'Sijali', 'Levi', 'Mwinuka', 'Female', 'HLF', '2005-12-20', '2023-01-10', 'ADM145F', 'Form Five', 'Tanzania', 'Mbeya', 'Levi Mwinuka', '0755123477', '$2y$10$YourDefaultHashHere', 'Teacher', 'Mbeya City', 'Mbeya Girls', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(244, 'S5098-0570', 'Naphtali', 'Judah', 'Mwakapalala', 'Male', 'HGF', '2005-04-02', '2023-01-10', 'ADM146M', 'Form Five', 'Tanzania', 'Tanga', 'Judah Mwakapalala', '0765123473', '$2y$10$YourDefaultHashHere', 'Businessman', 'Tanga City', 'Tanga Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(246, 'S5098-0512', 'Samuel', 'Gad', 'Mkumbo', 'Male', 'HGL', '2005-10-28', '2023-01-10', 'ADM148M', 'Form Five', 'Tanzania', 'Mwanza', 'Gad Mkumbo', '0711123473', '$2y$10$YourDefaultHashHere', 'Engineer', 'Ilemela, Mwanza', 'Mwanza Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(247, 'S5098-0524', 'Solomon', 'Asher', 'Mwagikana', 'Male', 'HGK', '2005-02-10', '2023-01-10', 'ADM149M', 'Form Five', 'Tanzania', 'Arusha', 'Asher Mwagikana', '0756123473', '$2y$10$YourDefaultHashHere', 'Tour Guide', 'Arusha City', 'Arusha Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(248, 'S5098-0532', 'Reuben', 'Naphtali', 'Mkumbo', 'Male', 'HKL', '2005-05-24', '2023-01-10', 'ADM150M', 'Form Five', 'Tanzania', 'Moshi', 'Naphtali Mkumbo', '0777123473', '$2y$10$YourDefaultHashHere', 'Hotel Owner', 'Moshi Municipality', 'Moshi Boys', NULL, NULL, NULL, 1, '2026-01-08 12:34:32', '2026-03-27 10:12:05', 0, NULL, NULL, '2026-02-06 08:32:29', 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, NULL),
(250, 'S5098-0501', 'laurent', 'jumanne', 'tadeo', 'Male', 'HGE', '2005-02-23', '2026-01-23', '12348s', 'Leavers', 'Tanzania', 'KIGOMA', 'JUMANNE TAZE', '255745607567', '$2y$10$YourDefaultHashHere', '', 'KIGOMA', '', '', '0000-00-00', '', 0, '2026-01-23 16:12:49', '2026-03-10 14:44:55', 1, '2026', 'Form Five', '2026-02-06 08:32:29', 1, 'Left', '2026', 'Retained', 12, 0, NULL, NULL),
(251, 'S5098-0505', 'tazan ', 'samsin', 'thazan', 'Male', 'HGE', '2021-05-07', '2026-02-07', 'e444', 'Form Five', 'Tanzania', 'kg', 'clemensia samson', '255619844080', '$2y$10$h4t5q//WxVXQDp00.TIRV.jYanT0ln.sdemzjFzeuJ0mcLADPHy56', 'teacher', 'uvinza', '', '', '0000-00-00', '', 1, '2026-02-07 17:17:01', '2026-03-27 10:12:05', 0, NULL, NULL, NULL, 1, 'Form Five', NULL, 'Retained', 12, 0, NULL, '2026-03-13 14:06:33'),
(408, 'S5098-0501', 'aaaaa', 'iouioj', '89y7y', 'Female', 'HGE', '2020-07-08', '2026-03-10', '121212', 'Form Five', 'Tanzania', 'tanga', 'hello', '255786655544', '$2y$10$dSUeOzpk/HlnVxLSPuxXleVU3bkOmJ7ieXbJo8Q1JBE5aOuMrqL7e', '', 'hi', '', '', '0000-00-00', '', 1, '2026-03-10 15:44:16', '2026-03-10 15:52:06', 0, NULL, NULL, NULL, 0, 'Active', NULL, 'Retained', 12, 0, NULL, '2026-03-10 18:46:05'),
(409, 'S5098-0502', 'princess', 'toy', 'toy', 'Female', 'HGE', '2016-05-08', '2026-03-27', 'y78', 'Form Five', 'Tanzania', 'kigoma', 'usa', '255768965970', '$2y$10$XqDSXRgczVpT5K8rBd3OTePIX.3tDrNNbceSDENENuGLjysyaepS.', 'engineer', 'dar', '', '', '0000-00-00', '', 1, '2026-03-27 10:12:05', '2026-03-27 10:12:53', 0, NULL, NULL, NULL, 0, 'Active', NULL, 'Retained', NULL, 0, NULL, '2026-03-27 13:12:53');

--
-- Triggers `students`
--
DELIMITER $$
CREATE TRIGGER `auto_graduate_form_six` BEFORE UPDATE ON `students` FOR EACH ROW BEGIN
    DECLARE current_academic_year VARCHAR(9);
    SET current_academic_year = CONCAT(YEAR(CURRENT_DATE)-1, '/', YEAR(CURRENT_DATE));
    
    IF NEW.is_leaver = TRUE AND OLD.is_leaver = FALSE AND OLD.class = 'Form Six' THEN
        SET NEW.graduation_status = 'Graduated';
        SET NEW.graduation_year = YEAR(CURRENT_DATE);
        
        INSERT INTO student_graduation_history (
            student_id, from_class, to_class, academic_year, 
            graduation_type, graduation_date, final_index_number,
            remarks, recorded_by
        ) VALUES (
            NEW.id, 'Form Six', 'Graduated', current_academic_year,
            'Graduation', CURRENT_DATE, NEW.index_number,
            CONCAT('Form Six graduation - ', IFNULL(NEW.school_transferred_to, 'Completed')),
            COALESCE(NEW.updated_by_admin, 1)
        );
        
        UPDATE student_equipment SET is_leaver = 1, leaver_year = YEAR(CURRENT_DATE) WHERE student_id = NEW.id;
        UPDATE student_dormitory SET status = 'Graduated' WHERE student_id = NEW.id AND status = 'Active';
    END IF;
    
    IF NEW.class = 'Form Six' AND OLD.class = 'Form Five' THEN
        SET NEW.promotion_status = 'Promoted to Form Six';
        SET NEW.previous_class = 'Form Five';
        SET NEW.class_changed_at = CURRENT_TIMESTAMP;
        
        INSERT INTO student_graduation_history (
            student_id, from_class, to_class, academic_year, 
            graduation_type, graduation_date, final_index_number,
            remarks, recorded_by
        ) VALUES (
            NEW.id, 'Form Five', 'Form Six', current_academic_year,
            'Promotion', CURRENT_DATE, NEW.index_number,
            'Promoted from Form Five to Form Six',
            COALESCE(NEW.updated_by_admin, 1)
        );
    END IF;
    
    IF NEW.class = 'Form Five' AND OLD.class = 'Form Five' AND NEW.is_leaver = FALSE AND OLD.is_leaver = FALSE THEN
        SET NEW.promotion_status = 'Retained';
    END IF;
    
    IF NEW.is_leaver = TRUE AND OLD.is_leaver = FALSE AND OLD.class != 'Form Six' THEN
        SET NEW.graduation_status = 'Left';
        SET NEW.graduation_year = YEAR(CURRENT_DATE);
        
        INSERT INTO student_graduation_history (
            student_id, from_class, to_class, academic_year, 
            graduation_type, graduation_date, final_index_number,
            remarks, recorded_by
        ) VALUES (
            NEW.id, OLD.class, 'Left', current_academic_year,
            IF(OLD.class = 'Form Five', 'Dropout', 'Transfer'), 
            CURRENT_DATE, NEW.index_number,
            CONCAT('Left school from ', OLD.class, ' - Reason: ', 
                   COALESCE(NEW.school_transferred_to, 'Not specified')),
            COALESCE(NEW.updated_by_admin, 1)
        );
    END IF;
    
    IF NEW.is_leaver = FALSE AND OLD.is_leaver = TRUE THEN
        SET NEW.graduation_status = NEW.class;
        SET NEW.graduation_year = NULL;
        SET NEW.is_returned = TRUE;
        
        UPDATE student_equipment SET is_leaver = 0, leaver_year = NULL WHERE student_id = NEW.id;
        UPDATE student_dormitory SET status = 'Active' WHERE student_id = NEW.id AND status IN ('Left', 'Graduated');
        
        UPDATE student_graduation_history 
        SET to_class = 'Returned', remarks = CONCAT('Returned to ', NEW.class)
        WHERE student_id = NEW.id AND to_class IN ('Left', 'Graduated') 
        AND id = (SELECT MAX(id) FROM student_graduation_history WHERE student_id = NEW.id);
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `auto_return_items_on_graduation` AFTER UPDATE ON `students` FOR EACH ROW BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_assignment_id INT;
    DECLARE v_item_id INT;
    DECLARE v_item_code VARCHAR(50);
    DECLARE graduation_reason VARCHAR(100);
    
    DECLARE cur_assignments CURSOR FOR 
        SELECT ma.id, ma.item_id, mi.item_code
        FROM maintenance_assignments ma
        JOIN maintenance_items mi ON ma.item_id = mi.id
        WHERE ma.student_id = NEW.id 
        AND ma.status = 'active';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    SET graduation_reason = CASE 
        WHEN NEW.graduation_status = 'Graduated' THEN 'Graduated from Form Six'
        WHEN NEW.graduation_status = 'Left' THEN 'Left school'
        ELSE NULL
    END;
    
    IF NEW.graduation_status IN ('Graduated', 'Left') AND OLD.graduation_status NOT IN ('Graduated', 'Left') THEN
        OPEN cur_assignments;
        
        read_loop: LOOP
            FETCH cur_assignments INTO v_assignment_id, v_item_id, v_item_code;
            IF done THEN
                LEAVE read_loop;
            END IF;
            
            UPDATE maintenance_assignments 
            SET status = 'returned',
                return_date = CURRENT_TIMESTAMP,
                return_condition = 'good',
                return_notes = CONCAT('Auto-returned: Student ', graduation_reason, ' (', NEW.graduation_year, ')')
            WHERE id = v_assignment_id;
            
            UPDATE maintenance_items 
            SET status = 'available'
            WHERE id = v_item_id;
            
            INSERT INTO maintenance_logs (item_id, log_type, user_type, user_id, admin_id, description)
            VALUES (v_item_id, 'return', 'student', NEW.id, NULL, 
                   CONCAT('Auto-returned ', v_item_code, ' - ', graduation_reason));
            
        END LOOP;
        
        CLOSE cur_assignments;
        
        UPDATE maintenance_staff_assignments 
        SET status = 'returned',
            return_date = CURRENT_TIMESTAMP,
            return_condition = 'good',
            return_notes = CONCAT('Auto-returned: ', graduation_reason)
        WHERE staff_id = NEW.id AND status = 'active';
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_equipment_on_leaver` AFTER UPDATE ON `students` FOR EACH ROW BEGIN
    IF NEW.is_leaver = TRUE AND OLD.is_leaver = FALSE THEN
        UPDATE student_equipment 
        SET is_leaver = TRUE, 
            leaver_year = YEAR(CURRENT_DATE)
        WHERE student_id = NEW.id;
    END IF;
    
    IF NEW.is_leaver = FALSE AND OLD.is_leaver = TRUE THEN
        UPDATE student_equipment 
        SET is_leaver = FALSE,
            leaver_year = NULL
        WHERE student_id = NEW.id;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `student_dormitory`
--

CREATE TABLE `student_dormitory` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `dormitory_id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `bed_number` varchar(10) DEFAULT NULL,
  `assigned_by` int(11) DEFAULT NULL COMMENT 'Admin ID who assigned',
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `status` enum('Active','Changed','Left','Graduated') DEFAULT 'Active',
  `notes` text DEFAULT NULL,
  `removed_date` timestamp NULL DEFAULT NULL,
  `removal_reason` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `student_dormitory`
--

INSERT INTO `student_dormitory` (`id`, `student_id`, `dormitory_id`, `room_id`, `bed_number`, `assigned_by`, `assigned_at`, `updated_at`, `status`, `notes`, `removed_date`, `removal_reason`) VALUES
(35, 38, 8, 112, '', 12, '2026-02-07 13:12:18', '2026-02-07 13:13:06', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(36, 61, 1, 1, '', 14, '2026-02-07 14:45:22', '2026-02-07 14:45:58', '', 'Assigned via dormitory.php', '2026-02-07 14:45:58', 'Auto-removed: Student deleted/marked as leaver'),
(37, 0, 8, 112, '', 12, '2026-02-08 18:14:27', '2026-02-08 18:28:23', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(38, 38, 9, 114, '', 12, '2026-02-08 18:14:38', '2026-02-08 18:31:52', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(39, 221, 1, 1, '', 12, '2026-02-08 18:14:50', '2026-02-08 18:33:19', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(40, 28, 2, 17, '', 12, '2026-02-08 18:15:01', '2026-02-08 18:34:08', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(41, 222, 1, 1, '', 12, '2026-02-08 18:15:12', '2026-02-08 18:33:38', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(42, 182, 1, 1, '', 12, '2026-02-08 18:15:26', '2026-02-08 18:33:14', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(43, 31, 5, 77, '', 12, '2026-02-08 18:15:54', '2026-02-08 18:32:23', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(44, 208, 10, 116, '', 12, '2026-02-08 18:16:03', '2026-02-08 18:32:09', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(45, 87, 7, 107, '', 12, '2026-02-08 18:16:13', '2026-02-08 18:32:01', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(46, 27, 1, 1, '', 12, '2026-02-08 18:18:29', '2026-02-08 18:33:51', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(47, 20, 1, 1, '', 12, '2026-02-08 18:18:38', '2026-02-08 18:34:02', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(48, 183, 1, 1, '', 12, '2026-02-08 18:18:46', '2026-02-08 18:33:57', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(49, 63, 1, 1, '', 12, '2026-02-08 18:18:56', '2026-02-08 18:33:25', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(50, 199, 1, 1, '', 12, '2026-02-08 18:19:08', '2026-02-08 18:33:31', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(51, 79, 1, 1, '', 12, '2026-02-08 18:22:00', '2026-02-08 18:33:44', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(52, 21, 2, 17, '', 12, '2026-02-08 18:22:10', '2026-02-08 18:33:09', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(53, 62, 1, 10, '', 12, '2026-02-08 18:22:53', '2026-02-08 18:33:02', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(54, 240, 2, 31, '', 12, '2026-02-08 18:23:09', '2026-02-08 18:34:16', 'Left', 'Assigned via female.php | Removed: Removed by admin via female.php', NULL, NULL),
(55, 0, 9, 114, '', 12, '2026-02-09 17:47:40', '2026-02-09 17:49:47', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(56, 206, 10, 116, '', 12, '2026-02-09 17:47:47', '2026-02-09 17:49:53', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(57, 246, 5, 87, 's1230', 12, '2026-03-08 02:39:36', '2026-03-08 02:40:47', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(58, 251, 8, 112, '', 31, '2026-03-13 22:33:30', '2026-03-13 22:37:02', 'Left', 'Assigned via male.php | Removed: Removed by admin via male.php', NULL, NULL),
(59, 38, 8, 112, '', 31, '2026-03-13 22:34:24', '2026-03-13 22:36:55', 'Left', 'Assigned via dormitory.php | Removed: Removed by admin via male.php', NULL, NULL),
(60, 251, 8, 112, '', 35, '2026-04-01 22:06:42', '2026-04-01 22:06:42', 'Active', 'Assigned via male.php', NULL, NULL);

--
-- Triggers `student_dormitory`
--
DELIMITER $$
CREATE TRIGGER `prevent_duplicate_active_assignment` BEFORE INSERT ON `student_dormitory` FOR EACH ROW BEGIN
    DECLARE v_active_count INT;
    
    -- If trying to insert an Active assignment
    IF NEW.status = 'Active' THEN
        -- Check if student already has an Active assignment
        SELECT COUNT(*) INTO v_active_count
        FROM student_dormitory 
        WHERE student_id = NEW.student_id 
        AND status = 'Active';
        
        IF v_active_count > 0 THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Student already has an active dormitory assignment!';
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `prevent_update_to_active_duplicate` BEFORE UPDATE ON `student_dormitory` FOR EACH ROW BEGIN
    DECLARE v_active_count INT;
    
    -- If trying to update to Active status
    IF NEW.status = 'Active' AND OLD.status != 'Active' THEN
        -- Check if student already has an Active assignment (other than this one)
        SELECT COUNT(*) INTO v_active_count
        FROM student_dormitory 
        WHERE student_id = NEW.student_id 
        AND status = 'Active'
        AND id != NEW.id;
        
        IF v_active_count > 0 THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Student already has an active dormitory assignment! Cannot have multiple active assignments.';
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_room_on_assignment` AFTER INSERT ON `student_dormitory` FOR EACH ROW BEGIN
    -- Only update if status is Active
    IF NEW.status = 'Active' THEN
        UPDATE dormitory_rooms 
        SET current_occupancy = current_occupancy + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.room_id
        AND current_occupancy < capacity;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_room_on_assignment_change` AFTER UPDATE ON `student_dormitory` FOR EACH ROW BEGIN
    -- If status changed from Active to something else
    IF OLD.status = 'Active' AND NEW.status != 'Active' THEN
        UPDATE dormitory_rooms 
        SET current_occupancy = GREATEST(current_occupancy - 1, 0),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.room_id;
    END IF;
    
    -- If status changed to Active from something else
    IF OLD.status != 'Active' AND NEW.status = 'Active' THEN
        UPDATE dormitory_rooms 
        SET current_occupancy = current_occupancy + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.room_id
        AND current_occupancy < capacity;
    END IF;
    
    -- If room changed
    IF OLD.room_id != NEW.room_id AND OLD.status = 'Active' THEN
        -- Decrease old room
        UPDATE dormitory_rooms 
        SET current_occupancy = GREATEST(current_occupancy - 1, 0),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.room_id;
        
        -- Increase new room
        UPDATE dormitory_rooms 
        SET current_occupancy = current_occupancy + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.room_id
        AND current_occupancy < capacity;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `student_equipment`
--

CREATE TABLE `student_equipment` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `is_leaver` tinyint(1) DEFAULT 0,
  `leaver_year` year(4) DEFAULT NULL,
  `leam` int(11) DEFAULT 0 COMMENT 'Number of leam',
  `hoe` tinyint(1) DEFAULT 0 COMMENT '0=No, 1=Yes',
  `lek` tinyint(1) DEFAULT 0 COMMENT 'For males only',
  `machet` tinyint(1) DEFAULT 0 COMMENT 'For females only',
  `slasher` tinyint(1) DEFAULT 0,
  `soft_broom` tinyint(1) DEFAULT 0,
  `hard_broom` tinyint(1) DEFAULT 0,
  `chelewa_broom` tinyint(1) DEFAULT 0,
  `bucket` int(11) DEFAULT 0 COMMENT 'Number of buckets',
  `total_equipment_count` int(11) DEFAULT 0,
  `equipment_notes` text DEFAULT NULL,
  `equipment_status` enum('Complete','Incomplete','None') DEFAULT 'None',
  `equipment_last_updated` timestamp NULL DEFAULT NULL,
  `contribution_target` decimal(10,2) DEFAULT 80000.00,
  `contribution_paid` decimal(10,2) DEFAULT 0.00,
  `contribution_balance` decimal(10,2) DEFAULT 80000.00,
  `contribution_status` enum('Paid','Partially Paid','Not Paid') DEFAULT 'Not Paid',
  `contribution_last_payment` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `student_equipment`
--

INSERT INTO `student_equipment` (`id`, `student_id`, `is_leaver`, `leaver_year`, `leam`, `hoe`, `lek`, `machet`, `slasher`, `soft_broom`, `hard_broom`, `chelewa_broom`, `bucket`, `total_equipment_count`, `equipment_notes`, `equipment_status`, `equipment_last_updated`, `contribution_target`, `contribution_paid`, `contribution_balance`, `contribution_status`, `contribution_last_payment`, `created_at`, `updated_at`) VALUES
(0, 246, 0, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 'None', NULL, 80000.00, 0.00, 80000.00, 'Not Paid', NULL, '2026-03-08 02:08:16', '2026-03-08 02:08:16'),
(0, 246, 0, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 'None', NULL, 80000.00, 0.00, 80000.00, 'Not Paid', NULL, '2026-03-08 02:11:38', '2026-03-08 02:11:38'),
(0, 53, 0, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 'None', NULL, 80000.00, 0.00, 80000.00, 'Not Paid', NULL, '2026-03-08 05:40:02', '2026-03-08 05:40:02'),
(0, 251, 0, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, 'None', NULL, 80000.00, 0.00, 80000.00, 'Not Paid', NULL, '2026-03-10 13:32:33', '2026-03-10 13:32:33');

--
-- Triggers `student_equipment`
--
DELIMITER $$
CREATE TRIGGER `update_equipment_stats` BEFORE UPDATE ON `student_equipment` FOR EACH ROW BEGIN
    DECLARE v_student_gender VARCHAR(10);
    DECLARE v_total_count INT DEFAULT 0;
    
    -- Pata gender ya mwanafunzi
    SELECT sex INTO v_student_gender 
    FROM students 
    WHERE id = NEW.student_id;
    
    -- Calculate total based on gender
    IF v_student_gender = 'Male' THEN
        -- For males: include lek, NOT machet
        SET v_total_count = 
            NEW.leam + 
            IF(NEW.hoe = 1, 1, 0) + 
            IF(NEW.lek = 1, 1, 0) +  -- lek for males
            IF(NEW.slasher = 1, 1, 0) + 
            IF(NEW.soft_broom = 1, 1, 0) + 
            IF(NEW.hard_broom = 1, 1, 0) + 
            IF(NEW.chelewa_broom = 1, 1, 0) + 
            NEW.bucket;
    ELSE
        -- For females: include machet, NOT lek
        SET v_total_count = 
            NEW.leam + 
            IF(NEW.hoe = 1, 1, 0) + 
            IF(NEW.machet = 1, 1, 0) +  -- machet for females
            IF(NEW.slasher = 1, 1, 0) + 
            IF(NEW.soft_broom = 1, 1, 0) + 
            IF(NEW.hard_broom = 1, 1, 0) + 
            IF(NEW.chelewa_broom = 1, 1, 0) + 
            NEW.bucket;
    END IF;
    
    -- SET STATUS: 12 items total (including 2 buckets)
    IF v_total_count >= 12 AND NEW.bucket >= 2 THEN
        SET NEW.equipment_status = 'Complete';
    ELSEIF v_total_count > 0 THEN
        SET NEW.equipment_status = 'Incomplete';
    ELSE
        SET NEW.equipment_status = 'None';
    END IF;
    
    SET NEW.total_equipment_count = v_total_count;
    
    -- Update contribution calculations
    SET NEW.contribution_balance = NEW.contribution_target - NEW.contribution_paid;
    
    IF NEW.contribution_paid >= NEW.contribution_target THEN
        SET NEW.contribution_status = 'Paid';
    ELSEIF NEW.contribution_paid > 0 THEN
        SET NEW.contribution_status = 'Partially Paid';
    ELSE
        SET NEW.contribution_status = 'Not Paid';
    END IF;
    
    -- Set updated timestamp
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `student_graduation_history`
--

CREATE TABLE `student_graduation_history` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `from_class` enum('Form Five','Form Six') NOT NULL,
  `to_class` enum('Form Five','Form Six','Graduated','Left') NOT NULL,
  `academic_year` varchar(9) NOT NULL COMMENT 'Format: 2024/2025',
  `graduation_type` enum('Promotion','Graduation','Transfer','Dropout','Repeating') DEFAULT 'Promotion',
  `graduation_date` date NOT NULL,
  `final_index_number` varchar(50) DEFAULT NULL,
  `certificate_number` varchar(100) DEFAULT NULL,
  `remarks` text DEFAULT NULL,
  `recorded_by` int(11) NOT NULL COMMENT 'Admin ID',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `student_graduation_history`
--

INSERT INTO `student_graduation_history` (`id`, `student_id`, `from_class`, `to_class`, `academic_year`, `graduation_type`, `graduation_date`, `final_index_number`, `certificate_number`, `remarks`, `recorded_by`, `created_at`) VALUES
(0, 205, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0502', NULL, 'Returned to Form Five', 12, '2026-02-06 08:31:50'),
(0, 18, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:17'),
(0, 1, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0521', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 1, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0521', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 10, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0543', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 10, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0543', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 11, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0531', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 11, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0531', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 14, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0522', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 14, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0522', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 15, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0570', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 15, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0570', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 39, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0528', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 39, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0528', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 40, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0539', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 40, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0539', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 41, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0551', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 41, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0551', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 42, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0554', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 42, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0554', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 43, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0567', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 43, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0567', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 44, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0572', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 44, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0572', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 45, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 45, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 46, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0518', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 46, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0518', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 47, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0523', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 47, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0523', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 48, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0537', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 48, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0537', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 49, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0548', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 49, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0548', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 50, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0556', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 50, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0556', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 51, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0564', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 51, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0564', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 52, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0575', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 52, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0575', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 53, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0510', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 53, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0510', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 54, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0512', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 54, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0512', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 55, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0526', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 55, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0526', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 56, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0540', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 56, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0540', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 57, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0549', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 57, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0549', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 58, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0557', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 58, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0557', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 69, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0506', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 69, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0506', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 70, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0520', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 70, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0520', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 71, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0529', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 71, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0529', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 72, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0538', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 72, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0538', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 73, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0544', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 73, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0544', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 74, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0552', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 74, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0552', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 75, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0565', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 75, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0565', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 76, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0574', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 76, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0574', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 77, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0508', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 77, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0508', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 78, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0519', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 78, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0519', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 89, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0546', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 89, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0546', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 90, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0558', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 90, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0558', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 91, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0563', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 91, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0563', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 92, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0569', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 92, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0569', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 93, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0507', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 93, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0507', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 94, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0517', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 94, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0517', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 95, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0524', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 95, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0524', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 96, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0535', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 96, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0535', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 97, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0545', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 97, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0545', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 98, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0559', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 98, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0559', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 184, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0533', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 184, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0533', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 189, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0505', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 189, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0505', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 190, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0511', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 190, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0511', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 191, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0530', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 191, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0530', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 192, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0534', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 192, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0534', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 193, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0547', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 193, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0547', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 194, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0555', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 194, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0555', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 195, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0562', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 195, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0562', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 196, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0576', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 196, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0576', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 197, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0504', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 197, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0504', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 198, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0516', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 198, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0516', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 209, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0542', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 209, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0542', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 210, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0561', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 210, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0561', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 211, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0566', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 211, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0566', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 212, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0571', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 212, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0571', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 213, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0502', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 213, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0502', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 214, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0514', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 214, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0514', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 215, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0527', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 215, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0527', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 216, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0532', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 216, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0532', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 217, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0550', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 217, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0550', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 218, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0560', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 218, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0560', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 229, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0509', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 229, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0509', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 230, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0513', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 230, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0513', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 231, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0525', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 231, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0525', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 232, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0536', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 232, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0536', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 233, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0541', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 233, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0541', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 234, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0553', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 234, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0553', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 235, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0568', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 235, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0568', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 236, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0573', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 236, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0573', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 237, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0503', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 237, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0503', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 238, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0515', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 238, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0515', NULL, 'Returned to Form Five', 12, '2026-02-06 08:32:29'),
(0, 17, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0563', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 17, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0563', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 19, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0504', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 19, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0504', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 20, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0510', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 20, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0510', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 21, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0518', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 21, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0518', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 22, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0531', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 22, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0531', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 23, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0538', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 23, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0538', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 24, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0552', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 24, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0552', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 25, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0555', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 25, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0555', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 26, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0567', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 26, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0567', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 27, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0506', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 27, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0506', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 28, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0508', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 28, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0508', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 30, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0511', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 30, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0511', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 31, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0520', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 31, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0520', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 32, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0534', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 32, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0534', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 33, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0541', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 33, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0541', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 34, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0547', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 34, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0547', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 35, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0562', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 35, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0562', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 36, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0574', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 36, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0574', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 37, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0502', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 37, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0502', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 38, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0513', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 38, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0513', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 59, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0554', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 59, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0554', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 60, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0575', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 60, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0575', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 61, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0503', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 61, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0503', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 62, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0512', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 62, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0512', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 63, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0526', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 63, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0526', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 64, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0529', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 64, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0529', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 66, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0550', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 66, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0550', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 67, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0556', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 67, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0556', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 68, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0571', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 68, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0571', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 79, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0521', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 79, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0521', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 81, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0543', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 81, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0543', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 82, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0548', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 82, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0548', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 83, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0557', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 83, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0557', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 84, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0565', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 84, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0565', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 86, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0509', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 86, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0509', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 87, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0523', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 87, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0523', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 88, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0533', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 88, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0533', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 179, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0559', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 179, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0559', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 180, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0568', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 180, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0568', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 182, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0516', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 182, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0516', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 183, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0519', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 183, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0519', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 185, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0544', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 185, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0544', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 186, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0551', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 186, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0551', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 187, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0558', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 187, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0558', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 188, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0569', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 188, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0569', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 199, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0524', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 199, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0524', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 200, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0530', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 200, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0530', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 201, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0539', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 201, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0539', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 202, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0546', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 202, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0546', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 203, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0564', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 203, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0564', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 204, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0572', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 204, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0572', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 206, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0517', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 206, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0517', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 207, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0522', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 207, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0522', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 208, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0532', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 208, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0532', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 219, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0553', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 219, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0553', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 220, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0570', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 220, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0570', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 221, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0507', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 221, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0507', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 222, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0514', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 222, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0514', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 223, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0528', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 223, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0528', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 224, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0536', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 224, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0536', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 225, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0540', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 225, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0540', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 226, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0545', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 226, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0545', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 227, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0561', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 227, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0561', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 228, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0566', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 228, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0566', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 239, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0525', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 239, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0525', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 240, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0537', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 240, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0537', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 241, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0542', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 241, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0542', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 242, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0549', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 242, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0549', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 243, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0560', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 243, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0560', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 244, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0573', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 244, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0573', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 246, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0515', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 246, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0515', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 247, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0527', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 247, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0527', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 248, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0535', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 248, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0535', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 250, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 250, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 251, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0505', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 251, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0505', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:32:29'),
(0, 45, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 08:41:55'),
(0, 45, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Six', 12, '2026-02-06 09:03:35'),
(0, 213, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 09:47:43'),
(0, 237, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 09:47:49'),
(0, 213, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 10:20:47'),
(0, 45, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 10:20:57'),
(0, 250, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 12:35:29'),
(0, 17, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0562', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 17, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0562', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 19, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0503', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 19, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0503', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 20, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0509', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 20, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0509', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 21, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0517', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 21, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0517', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 22, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0530', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 22, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0530', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 23, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0537', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 23, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0537', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 24, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0551', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 24, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0551', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 25, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0554', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 25, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0554', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 26, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0566', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 26, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0566', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 27, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0505', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 27, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0505', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 28, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0507', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 28, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0507', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 30, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0510', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 30, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0510', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 31, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0519', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 31, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0519', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 32, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0533', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 32, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0533', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 33, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0540', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23');
INSERT INTO `student_graduation_history` (`id`, `student_id`, `from_class`, `to_class`, `academic_year`, `graduation_type`, `graduation_date`, `final_index_number`, `certificate_number`, `remarks`, `recorded_by`, `created_at`) VALUES
(0, 33, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0540', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 34, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0546', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 34, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0546', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 35, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0561', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 35, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0561', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 36, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0573', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 36, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0573', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 37, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 37, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 38, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0512', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 38, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0512', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 59, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0553', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 59, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0553', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 60, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0574', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 60, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0574', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 61, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0502', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 61, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0502', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 62, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0511', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 62, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0511', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 63, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0525', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 63, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0525', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 64, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0528', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 64, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0528', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 66, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0549', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 66, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0549', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 67, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0555', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 67, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0555', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 68, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0570', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 68, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0570', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 79, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0520', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 79, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0520', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 81, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0542', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 81, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0542', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 82, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0547', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 82, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0547', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 83, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0556', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 83, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0556', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 84, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0564', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 84, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0564', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 86, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0508', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 86, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0508', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 87, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0522', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 87, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0522', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 88, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0532', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 88, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0532', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 179, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0558', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 179, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0558', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 180, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0567', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 180, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0567', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 182, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0515', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 182, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0515', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 183, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0518', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 183, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0518', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 185, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0543', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 185, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0543', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 186, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0550', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 186, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0550', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 187, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0557', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 187, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0557', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 188, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0568', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 188, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0568', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 199, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0523', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 199, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0523', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 200, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0529', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 200, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0529', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 201, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0538', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 201, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0538', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 202, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0545', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 202, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0545', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 203, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0563', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 203, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0563', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 204, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0571', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 204, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0571', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 206, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0516', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 206, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0516', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 207, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0521', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 207, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0521', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 208, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0531', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 208, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0531', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 219, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0552', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 219, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0552', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 220, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0569', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 220, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0569', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 221, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0506', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 221, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0506', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 222, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0513', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 222, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0513', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 223, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0527', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 223, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0527', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 224, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0535', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 224, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0535', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 225, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0539', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 225, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0539', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 226, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0544', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 226, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0544', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 227, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0560', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 227, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0560', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 228, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0565', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 228, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0565', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 239, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0524', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 239, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0524', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 240, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0536', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 240, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0536', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 241, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0541', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 241, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0541', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 242, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0548', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 242, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0548', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 243, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0559', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 243, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0559', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 244, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0572', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 244, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0572', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 246, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0514', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 246, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0514', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 247, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0526', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 247, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0526', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 248, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0534', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 248, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0534', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 251, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0504', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 251, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0504', NULL, 'Returned to Form Five', 12, '2026-02-06 12:40:23'),
(0, 1, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0525', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 1, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0525', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 2, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0502', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 2, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0502', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 7, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0563', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 7, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0563', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 9, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0506', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 9, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0506', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 10, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0547', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 10, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0547', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 11, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0535', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 11, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0535', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 13, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0521', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 13, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0521', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 14, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0526', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 14, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0526', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 15, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0576', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 15, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0576', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 18, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0504', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 18, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0504', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 39, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0532', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 39, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0532', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 40, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0543', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 40, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0543', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 41, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0556', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 41, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0556', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 42, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0559', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 42, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0559', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 43, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0573', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 43, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0573', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 44, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0578', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 44, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0578', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 46, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0522', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 46, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0522', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 47, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0527', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 47, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0527', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 48, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0541', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 48, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0541', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 49, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0553', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 49, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0553', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 50, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0561', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 50, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0561', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 51, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0570', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 51, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0570', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 52, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0581', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 52, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0581', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 53, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0513', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 53, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0513', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 54, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0515', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 54, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0515', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 55, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0530', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 55, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0530', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 56, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0544', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 56, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0544', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 57, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0554', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 57, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0554', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 58, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0562', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 58, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0562', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 65, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0550', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 65, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0550', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 69, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0508', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 69, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0508', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 70, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0524', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 70, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0524', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 71, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0533', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 71, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0533', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 72, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0542', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 72, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0542', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 73, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0548', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 73, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0548', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 74, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0557', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 74, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0557', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 75, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0571', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 75, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0571', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 76, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0580', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 76, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0580', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 77, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0510', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 77, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0510', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 78, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0523', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 78, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0523', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 85, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0511', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 85, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0511', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 89, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0551', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 89, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0551', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 90, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0564', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 90, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0564', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 91, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0569', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 91, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0569', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 92, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0575', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 92, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0575', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 93, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0509', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 93, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0509', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 94, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0520', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 94, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0520', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 95, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0528', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 95, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0528', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 96, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0539', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 96, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0539', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 97, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0549', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 97, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0549', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 98, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0565', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 98, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0565', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 184, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0537', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 184, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0537', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 189, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0507', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 189, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0507', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 190, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0514', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 190, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0514', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 191, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0534', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 191, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0534', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 192, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0538', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 192, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0538', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 193, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0552', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 193, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0552', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 194, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0560', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 194, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0560', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 195, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0568', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 195, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0568', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 196, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0582', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 196, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0582', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 197, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0503', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 197, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0503', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 198, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0519', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 198, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0519', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 205, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0505', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 205, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0505', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 209, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0546', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 209, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0546', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 210, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0567', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 210, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0567', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 211, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0572', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 211, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0572', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 212, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0577', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 212, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0577', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 214, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0517', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 214, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0517', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 215, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0531', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 215, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0531', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 216, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0536', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 216, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0536', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 217, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0555', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 217, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0555', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 218, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0566', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 218, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0566', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 229, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0512', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 229, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0512', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 230, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0516', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 230, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0516', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 231, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0529', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 231, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0529', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 232, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0540', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 232, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0540', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 233, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0545', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 233, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0545', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 234, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0558', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 234, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0558', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 235, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0574', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 235, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0574', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 236, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0579', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 236, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0579', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 237, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 237, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 238, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0518', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 238, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-06', 'S5098-0518', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-06 12:40:23'),
(0, 45, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 12:45:15'),
(0, 213, 'Form Five', 'Left', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Left school from Form Five - Reason: Not specified', 12, '2026-02-06 15:38:16'),
(0, 250, 'Form Five', 'Left', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Left school from Form Five - Reason: ', 12, '2026-02-06 15:38:20'),
(0, 37, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-06', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-06 15:38:27'),
(0, 237, 'Form Six', 'Graduated', '2025/2026', 'Graduation', '2026-02-06', 'S5098-0501', NULL, 'Form Six graduation - Completed', 12, '2026-02-06 15:38:49'),
(0, 86, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-07', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-07 09:12:47'),
(0, 86, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 09:36:30'),
(0, 86, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 09:44:48'),
(0, 86, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:18:31'),
(0, 86, 'Form Five', 'Left', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Left school from Form Five - Reason: ', 12, '2026-02-07 10:22:20'),
(0, 37, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:31:46'),
(0, 37, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:32:39'),
(0, 37, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:36:28'),
(0, 37, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:37:50'),
(0, 61, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:57:36'),
(0, 61, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 12, '2026-02-07 10:59:25'),
(0, 19, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-07', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 12, '2026-02-07 10:59:50'),
(0, 197, 'Form Six', '', '2025/2026', 'Graduation', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Six', 12, '2026-02-07 11:10:08'),
(0, 61, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 14, '2026-02-07 14:34:57'),
(0, 61, 'Form Five', '', '2025/2026', '', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 14, '2026-02-07 14:34:57'),
(0, 61, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 14, '2026-02-07 14:45:58'),
(0, 61, 'Form Five', '', '2025/2026', '', '2026-02-07', 'S5098-0501', NULL, 'Returned to Form Five', 14, '2026-02-07 14:45:58'),
(0, 61, 'Form Five', 'Form Six', '2025/2026', 'Promotion', '2026-02-07', 'S5098-0501', NULL, 'Promoted from Form Five to Form Six', 14, '2026-02-07 14:51:41'),
(0, 0, 'Form Five', '', '2025/2026', 'Dropout', '2026-02-07', 'S5098-0503', NULL, 'Returned to Form Five', 14, '2026-02-07 17:17:47'),
(0, 0, 'Form Five', '', '2025/2026', '', '2026-02-07', 'S5098-0503', NULL, 'Returned to Form Five', 14, '2026-02-07 17:17:47');

-- --------------------------------------------------------

--
-- Table structure for table `student_leavers`
--

CREATE TABLE `student_leavers` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `index_number` varchar(50) DEFAULT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `combination` varchar(10) NOT NULL,
  `class_left` enum('Form Five','Form Six') NOT NULL,
  `year_left` year(4) NOT NULL,
  `reason` varchar(200) DEFAULT 'Graduation',
  `left_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `returned` tinyint(1) DEFAULT 0,
  `returned_at` timestamp NULL DEFAULT NULL,
  `leaver_type` enum('Graduated','Transferred','Dismissed','Other') DEFAULT 'Transferred'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `student_leavers`
--

INSERT INTO `student_leavers` (`id`, `student_id`, `index_number`, `first_name`, `last_name`, `combination`, `class_left`, `year_left`, `reason`, `left_at`, `returned`, `returned_at`, `leaver_type`) VALUES
(0, 205, 'S5098-0502', 'Judah', 'Mwagike', 'HGE', 'Form Five', '2026', 'Transferred from Form Five', '2026-02-06 08:31:50', 1, '2026-02-06 08:33:08', 'Transferred'),
(0, 18, 'S5098-0501', 'JANETH', 'WECH', 'HGE', 'Form Five', '2026', 'Transferred from Form Five', '2026-02-06 08:32:17', 1, '2026-02-06 08:33:08', 'Transferred'),
(0, 1, 'S5098-0521', 'TAZE', 'TADEO', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 10, 'S5098-0543', 'jamary', 'mussa', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 11, 'S5098-0531', 'alu', 'mussa', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 14, 'S5098-0522', 'aujenia', 'TADEO', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 15, 'S5098-0570', 'franc', 'leo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 39, 'S5098-0528', 'Rehema', 'Kondo', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 40, 'S5098-0539', 'Pendo', 'Mloka', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 41, 'S5098-0551', 'Tumaini', 'Kibwana', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 42, 'S5098-0554', 'Furaha', 'Mwakyembe', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 43, 'S5098-0567', 'Upendo', 'Kamala', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 44, 'S5098-0572', 'Imani', 'Mkumbo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 45, 'S5098-0501', 'Bibi', 'Shekimweri', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 46, 'S5098-0518', 'Mama', 'Kadanya', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 47, 'S5098-0523', 'Dada', 'Mgeni', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 48, 'S5098-0537', 'Mtoto', 'Mwinyi', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 49, 'S5098-0548', 'Rajabu', 'Mfugale', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 50, 'S5098-0556', 'Hamisi', 'Kivuyo', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 51, 'S5098-0564', 'Kassim', 'Mkwizu', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 52, 'S5098-0575', 'Suleiman', 'Kijaji', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 53, 'S5098-0510', 'Yusuf', 'Mtei', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:08', 'Graduated'),
(0, 54, 'S5098-0512', 'Ali', 'Mushi', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 55, 'S5098-0526', 'Mohamed', 'Kibwana', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 56, 'S5098-0540', 'Rashid', 'Mtemvu', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 57, 'S5098-0549', 'Saidi', 'Kavishe', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 58, 'S5098-0557', 'Hemed', 'Mariki', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 69, 'S5098-0506', 'Maimuna', 'Mkubwa', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 70, 'S5098-0520', 'Mwanajuma', 'Kibao', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 71, 'S5098-0529', 'Tabu', 'Kikwete', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 72, 'S5098-0538', 'Mwajuma', 'Kibona', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 73, 'S5098-0544', 'Jamila', 'Mteule', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 74, 'S5098-0552', 'Abdallah', 'Mpemba', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 75, 'S5098-0565', 'Kombo', 'Kiwia', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 76, 'S5098-0574', 'Kondo', 'Kilonzo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 77, 'S5098-0508', 'Mzee', 'Kiwelu', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 78, 'S5098-0519', 'Massawe', 'Kimario', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 89, 'S5098-0546', 'Lydia', 'Mabula', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 90, 'S5098-0558', 'Miriam', 'Mgimwa', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 91, 'S5098-0563', 'Hannah', 'Mwakalukwa', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 92, 'S5098-0569', 'Elizabeth', 'Mfupi', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 93, 'S5098-0507', 'Mary', 'Mkumbo', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 94, 'S5098-0517', 'Ezekiel', 'Mnyampala', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 95, 'S5098-0524', 'Isaiah', 'Mwakipesile', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 96, 'S5098-0535', 'Malachi', 'Mwagike', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 97, 'S5098-0545', 'Jonah', 'Mkude', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 98, 'S5098-0559', 'Obadiah', 'Mwalongo', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 184, 'S5098-0533', 'Benjamin', 'Mwangosi', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 189, 'S5098-0505', 'Magdalena', 'Mteule', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 190, 'S5098-0511', 'Agnes', 'Mkumbo', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 191, 'S5098-0530', 'Veronica', 'Mwagikana', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 192, 'S5098-0534', 'Christina', 'Mkumbo', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 193, 'S5098-0547', 'Monica', 'Mwakalukwa', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 194, 'S5098-0555', 'Gideon', 'Mkumbo', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 195, 'S5098-0562', 'Dan', 'Mtepa', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 196, 'S5098-0576', 'Zebulun', 'Mwangoka', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 197, 'S5098-0504', 'Issachar', 'Mkinda', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 198, 'S5098-0516', 'Ephraim', 'Mwakasaka', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 209, 'S5098-0542', 'Jackline', 'Mtega', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 210, 'S5098-0561', 'Vivian', 'Mwangoka', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 211, 'S5098-0566', 'Sylvia', 'Mkude', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 212, 'S5098-0571', 'Gloria', 'Mwangosi', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 213, 'S5098-0502', 'Diana', 'Mkuchika', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 214, 'S5098-0514', 'Asher', 'Mwaibula', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 215, 'S5098-0527', 'Naphtali', 'Mwinuka', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 216, 'S5098-0532', 'Benjamin', 'Mwakapalala', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 217, 'S5098-0550', 'Samuel', 'Mteule', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 218, 'S5098-0560', 'Solomon', 'Mkumbo', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 229, 'S5098-0509', 'Stella', 'Mwanga', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 230, 'S5098-0513', 'Anita', 'Mtepa', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 231, 'S5098-0525', 'Judith', 'Mwakalinga', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 232, 'S5098-0536', 'Martha', 'Mwakalukwa', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 233, 'S5098-0541', 'Esther', 'Mwagike', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 234, 'S5098-0553', 'Dan', 'Mkude', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 235, 'S5098-0568', 'Zebulun', 'Mwalongo', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 236, 'S5098-0573', 'Issachar', 'Mwandosya', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 237, 'S5098-0503', 'Gad', 'Mtega', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 238, 'S5098-0515', 'Asher', 'Mwangoka', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 08:32:29', 1, '2026-02-06 08:33:09', 'Graduated'),
(0, 250, 'S5098-0501', 'laurent', 'tadeo', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:35:29', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 17, 'S5098-0562', 'THAZAN', 'TZONE', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 19, 'S5098-0503', 'Neema', 'Mrema', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 20, 'S5098-0509', 'Grace', 'Mkenda', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 21, 'S5098-0517', 'Asha', 'Juma', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 22, 'S5098-0530', 'Fatuma', 'Hassan', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 23, 'S5098-0537', 'Aisha', 'Said', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 24, 'S5098-0551', 'Zainab', 'Abdallah', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 25, 'S5098-0554', 'Mariam', 'Khamis', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 26, 'S5098-0566', 'Happiness', 'Mpenda', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 27, 'S5098-0505', 'Sarah', 'Mbowe', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 28, 'S5098-0507', 'Catherine', 'Kibona', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 30, 'S5098-0510', 'Joseph', 'Chamwela', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 31, 'S5098-0519', 'David', 'Mwingira', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 32, 'S5098-0533', 'James', 'Kapinga', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 33, 'S5098-0540', 'Peter', 'Nyanda', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 34, 'S5098-0546', 'Michael', 'Mpemba', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 35, 'S5098-0561', 'Simon', 'Kisare', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 36, 'S5098-0573', 'Paul', 'Mtonga', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:06', 'Graduated'),
(0, 37, 'S5098-0501', 'Mark', 'Lyimo', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 38, 'S5098-0512', 'Luke', 'Mosha', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 59, 'S5098-0553', 'Halima', 'Kishimbo', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 60, 'S5098-0574', 'Zuhura', 'Mwambene', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 61, 'S5098-0502', 'Mwanahawa', 'Kitwana', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 62, 'S5098-0511', 'Khadija', 'Mpango', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 63, 'S5098-0525', 'Sauda', 'Kibiriti', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 64, 'S5098-0528', 'Bakari', 'Mwandu', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 66, 'S5098-0549', 'Ramadhani', 'Kibanda', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 67, 'S5098-0555', 'Mwinyi', 'Msangi', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 68, 'S5098-0570', 'Makame', 'Kijiko', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 79, 'S5098-0520', 'Ester', 'Minja', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 81, 'S5098-0542', 'Ruth', 'Mwalukasa', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 82, 'S5098-0547', 'Naomi', 'Mwakalinga', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 83, 'S5098-0556', 'Rachel', 'Mtepa', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 84, 'S5098-0564', 'Elia', 'Mkumbo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 87, 'S5098-0522', 'Nathan', 'Mkama', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 88, 'S5098-0532', 'Isaac', 'Mkwawa', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 179, 'S5098-0558', 'Rose', 'Mwandosya', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 180, 'S5098-0567', 'Joyce', 'Mkenda', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 182, 'S5098-0515', 'Teresia', 'Mwangoka', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 183, 'S5098-0518', 'Consolata', 'Mkude', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 185, 'S5098-0543', 'Samuel', 'Mkuchika', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 186, 'S5098-0550', 'Solomon', 'Mwaibula', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 187, 'S5098-0557', 'Reuben', 'Mwinuka', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 188, 'S5098-0568', 'Levi', 'Mwakapalala', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 199, 'S5098-0523', 'Patricia', 'Mngumi', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 200, 'S5098-0529', 'Eunice', 'Mkumbo', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 201, 'S5098-0538', 'Beatrice', 'Mwanga', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 202, 'S5098-0545', 'Leticia', 'Mtepa', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 203, 'S5098-0563', 'Victoria', 'Mwakalinga', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 204, 'S5098-0571', 'Manasseh', 'Mwakalukwa', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 206, 'S5098-0516', 'Zebulun', 'Mkude', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 207, 'S5098-0521', 'Issachar', 'Mwalongo', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 208, 'S5098-0531', 'Gad', 'Mwandosya', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 219, 'S5098-0552', 'Flora', 'Mwagikana', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 220, 'S5098-0569', 'Linda', 'Mkumbo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 221, 'S5098-0506', 'Tatu', 'Mwakalukwa', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 222, 'S5098-0513', 'Mwajuma', 'Mkumbo', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 223, 'S5098-0527', 'Zawadi', 'Mtepa', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 224, 'S5098-0535', 'Reuben', 'Mwangoka', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 225, 'S5098-0539', 'Levi', 'Mkinda', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 226, 'S5098-0544', 'Judah', 'Mwakasaka', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 227, 'S5098-0560', 'Simeon', 'Mngumi', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 228, 'S5098-0565', 'Gad', 'Mkumbo', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 239, 'S5098-0524', 'Paulina', 'Mkude', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 240, 'S5098-0536', 'Salome', 'Mwangosi', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 241, 'S5098-0541', 'Rehema', 'Mkuchika', 'KLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 242, 'S5098-0548', 'Pili', 'Mwaibula', 'EGM', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 243, 'S5098-0559', 'Sijali', 'Mwinuka', 'HLF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 244, 'S5098-0572', 'Naphtali', 'Mwakapalala', 'HGF', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 246, 'S5098-0514', 'Samuel', 'Mkumbo', 'HGL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 247, 'S5098-0526', 'Solomon', 'Mwagikana', 'HGK', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 248, 'S5098-0534', 'Reuben', 'Mkumbo', 'HKL', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 251, 'S5098-0504', 'patrick', 'camara', 'HGE', 'Form Six', '2026', 'Graduated from Form Six', '2026-02-06 12:40:23', 1, '2026-02-06 12:41:07', 'Graduated'),
(0, 0, 'S5098-0503', 'tazan ', 'thazan', 'HGE', 'Form Five', '2026', 'Transferred from Form Five', '2026-02-07 17:17:47', 1, '2026-02-07 17:18:28', 'Transferred');

-- --------------------------------------------------------

--
-- Table structure for table `student_login_attempts`
--

CREATE TABLE `student_login_attempts` (
  `id` int(11) NOT NULL,
  `identifier` varchar(255) NOT NULL,
  `success` tinyint(1) DEFAULT 0,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `attempt_time` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `student_login_attempts`
--

INSERT INTO `student_login_attempts` (`id`, `identifier`, `success`, `ip_address`, `user_agent`, `attempt_time`) VALUES

--
-- Table structure for table `student_login_logs`
--

CREATE TABLE `student_login_logs` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `action` varchar(225) NOT NULL,
  `user_agent` text DEFAULT NULL,
  `login_time` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


-- --------------------------------------------------------

--
-- Table structure for table `subject_result_entry_log`
--

CREATE TABLE `subject_result_entry_log` (
  `id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `subject` varchar(20) NOT NULL,
  `exam_type_id` int(11) NOT NULL,
  `form_level` enum('Form Five','Form Six') NOT NULL,
  `entry_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `ip_address` varchar(45) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `subject_teacher_assignments`
--

CREATE TABLE `subject_teacher_assignments` (
  `id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `subject` varchar(20) NOT NULL,
  `form_level` enum('Form Five','Form Six') NOT NULL,
  `academic_year` year(4) NOT NULL,
  `is_primary` tinyint(1) DEFAULT 0,
  `can_enter_results` tinyint(1) DEFAULT 1,
  `assigned_by` int(11) NOT NULL,
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `support_messages`
--

CREATE TABLE `support_messages` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `user_type` enum('admin','student') NOT NULL DEFAULT 'admin',
  `user_name` varchar(200) NOT NULL,
  `user_role` varchar(100) DEFAULT NULL,
  `subject` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `status` enum('pending','replied','closed') DEFAULT 'pending',
  `priority` enum('low','normal','high','urgent') DEFAULT 'normal',
  `assigned_to` int(11) DEFAULT NULL COMMENT 'Admin ID who is handling this',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `support_messages`
--

INSERT INTO `support_messages` (`id`, `user_id`, `user_type`, `user_name`, `user_role`, `subject`, `message`, `status`, `priority`, `assigned_to`, `created_at`, `updated_at`) VALUES
(1, 29, 'admin', 'bamfu bamfu', 'PS', 'ninashida ya system', 'naomba msaada', 'closed', 'normal', NULL, '2026-03-14 15:14:23', '2026-04-02 10:39:12'),
(2, 35, 'admin', 'agness taze', 'Dormitory Teacher', 'hello', 'How can I view my results?', 'pending', 'normal', NULL, '2026-04-01 22:09:58', '2026-04-01 22:09:58');

-- --------------------------------------------------------

--
-- Table structure for table `support_replies`
--

CREATE TABLE `support_replies` (
  `id` int(11) NOT NULL,
  `message_id` int(11) NOT NULL,
  `reply_by` int(11) NOT NULL COMMENT 'Admin ID who replied',
  `reply_by_name` varchar(200) NOT NULL,
  `reply_by_role` varchar(100) DEFAULT NULL,
  `reply_message` text NOT NULL,
  `is_private` tinyint(1) DEFAULT 0 COMMENT '1 = private note, 0 = public reply',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `support_replies`
--

INSERT INTO `support_replies` (`id`, `message_id`, `reply_by`, `reply_by_name`, `reply_by_role`, `reply_message`, `is_private`, `created_at`) VALUES
(1, 1, 31, 'Tzone TZ', 'Head Master', 'msaada gani huo', 0, '2026-03-14 15:15:22');

-- --------------------------------------------------------

--
-- Table structure for table `teams`
--

CREATE TABLE `teams` (
  `id` int(11) NOT NULL,
  `team_name` varchar(100) NOT NULL,
  `team_type` enum('Form Five Combination','Form Six Combination','Staff') NOT NULL,
  `combination_code` varchar(10) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `teams`
--

INSERT INTO `teams` (`id`, `team_name`, `team_type`, `combination_code`, `is_active`, `created_at`) VALUES
(1, 'HGE Form Five', 'Form Five Combination', 'HGE', 1, '2026-03-31 16:51:42'),
(2, 'HGL Form Five', 'Form Five Combination', 'HGL', 1, '2026-03-31 16:51:42'),
(3, 'HGK Form Five', 'Form Five Combination', 'HGK', 1, '2026-03-31 16:51:42'),
(4, 'HKL Form Five', 'Form Five Combination', 'HKL', 1, '2026-03-31 16:51:42'),
(5, 'KLF Form Five', 'Form Five Combination', 'KLF', 1, '2026-03-31 16:51:42'),
(6, 'EGM Form Five', 'Form Five Combination', 'EGM', 1, '2026-03-31 16:51:42'),
(7, 'HLF Form Five', 'Form Five Combination', 'HLF', 1, '2026-03-31 16:51:42'),
(8, 'HGF Form Five', 'Form Five Combination', 'HGF', 1, '2026-03-31 16:51:42'),
(9, 'HGE Form Six', 'Form Six Combination', 'HGE', 1, '2026-03-31 16:51:42'),
(10, 'HGL Form Six', 'Form Six Combination', 'HGL', 1, '2026-03-31 16:51:42'),
(11, 'HGK Form Six', 'Form Six Combination', 'HGK', 1, '2026-03-31 16:51:42'),
(12, 'HKL Form Six', 'Form Six Combination', 'HKL', 1, '2026-03-31 16:51:42'),
(13, 'KLF Form Six', 'Form Six Combination', 'KLF', 1, '2026-03-31 16:51:42'),
(14, 'EGM Form Six', 'Form Six Combination', 'EGM', 1, '2026-03-31 16:51:42'),
(15, 'HLF Form Six', 'Form Six Combination', 'HLF', 1, '2026-03-31 16:51:42'),
(16, 'HGF Form Six', 'Form Six Combination', 'HGF', 1, '2026-03-31 16:51:42'),
(17, 'Staff Team', 'Staff', NULL, 1, '2026-03-31 16:51:42');

-- --------------------------------------------------------

--
-- Table structure for table `team_participants`
--

CREATE TABLE `team_participants` (
  `id` int(11) NOT NULL,
  `team_id` int(11) NOT NULL,
  `participant_type` enum('Student','Staff') NOT NULL,
  `participant_id` int(11) NOT NULL,
  `position` varchar(50) DEFAULT NULL,
  `jersey_number` varchar(10) DEFAULT NULL,
  `is_captain` tinyint(1) DEFAULT 0,
  `joined_date` date DEFAULT NULL,
  `status` enum('Active','Inactive') DEFAULT 'Active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `theme_settings`
--

CREATE TABLE `theme_settings` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `theme_settings`
--

INSERT INTO `theme_settings` (`id`, `admin_id`, `setting_key`, `setting_value`, `updated_at`) VALUES
(1, 31, 'primary', '#3B9DB3', '2026-03-14 18:01:34'),
(2, 31, 'primary_dark', '#2d7c8f', '2026-03-14 18:01:34'),
(3, 31, 'primary_light', '#8bc5d6', '2026-03-14 18:01:34'),
(4, 31, 'light', '#f8f9fa', '2026-03-14 10:39:51'),
(5, 31, 'white', '#ffffff', '2026-03-13 22:58:57'),
(6, 31, 'gray', '#e9ecef', '2026-03-14 10:39:51'),
(7, 31, 'text', '#333333', '2026-03-14 09:20:56'),
(8, 31, 'text_light', '#666666', '2026-03-13 22:58:57'),
(9, 31, 'border', '#e0e0e0', '2026-03-14 09:20:56'),
(10, 31, 'success', '#28a745', '2026-03-14 09:20:56'),
(11, 31, 'danger', '#dc3545', '2026-03-14 09:20:56'),
(12, 31, 'warning', '#ffc107', '2026-03-14 09:20:56'),
(13, 31, 'info', '#17a2b8', '2026-03-14 09:20:56'),
(14, 14, 'primary', '#3B9DB3', '2026-03-14 17:49:15'),
(15, 14, 'primary_dark', '#2d7c8f', '2026-03-14 17:49:15'),
(16, 14, 'primary_light', '#8bc5d6', '2026-03-14 17:49:15'),
(17, 14, 'light', '', '2026-03-14 08:39:55'),
(18, 14, 'white', '', '2026-03-14 08:39:55'),
(19, 14, 'gray', '', '2026-03-14 08:39:55'),
(20, 14, 'text', '#333333', '2026-04-02 07:26:29'),
(21, 14, 'text_light', '#666666', '2026-03-14 12:47:19'),
(22, 14, 'border', '#e0e0e0', '2026-03-14 08:34:06'),
(23, 14, 'success', '#28a745', '2026-03-14 08:34:06'),
(24, 14, 'danger', '#dc3545', '2026-03-14 08:34:06'),
(25, 14, 'warning', '#ffc107', '2026-03-14 08:34:06'),
(26, 14, 'info', '#17a2b8', '2026-03-14 08:34:06'),
(27, 14, 'coral', '#FF7F50', '2026-03-14 08:39:55'),
(28, 14, 'forest_green', '#2E7D32', '2026-03-14 08:39:55'),
(29, 14, 'lime_green', '#63E07E', '2026-03-14 08:39:55'),
(30, 14, 'sky_blue', '#66d9ff', '2026-03-14 08:39:55'),
(31, 14, 'aqua_blue', '#4dd2ff', '2026-03-14 08:39:55'),
(32, 31, 'coral', '#FF7F50', '2026-03-14 09:01:50'),
(33, 31, 'forest_green', '#2E7D32', '2026-03-14 18:01:34'),
(34, 31, 'lime_green', '#63E07E', '2026-03-14 09:01:50'),
(35, 31, 'sky_blue', '#66d9ff', '2026-03-14 09:01:50'),
(36, 31, 'aqua_blue', '#4dd2ff', '2026-03-14 09:01:50'),
(37, 26, 'primary', '#63E07E', '2026-03-14 13:03:41'),
(38, 26, 'primary_dark', '#4CAF50', '2026-03-14 13:03:41'),
(39, 26, 'primary_light', '#A5D6A7', '2026-03-14 13:03:41'),
(40, 26, 'text', '#333333', '2026-03-14 12:39:46'),
(41, 26, 'text_light', '#666666', '2026-03-14 12:39:46'),
(42, 26, 'border', '#e0e0e0', '2026-03-14 12:39:46'),
(43, 26, 'success', '#28a745', '2026-03-14 12:39:46'),
(44, 26, 'danger', '#dc3545', '2026-03-14 12:39:46'),
(45, 26, 'warning', '#ffc107', '2026-03-14 12:39:46'),
(46, 26, 'info', '#17a2b8', '2026-03-14 12:39:46'),
(47, 26, 'coral', '#FF7F50', '2026-03-14 12:39:46'),
(48, 26, 'forest_green', '#2E7D32', '2026-03-14 12:39:46'),
(49, 26, 'lime_green', '#63E07E', '2026-03-14 12:39:46'),
(50, 26, 'sky_blue', '#66d9ff', '2026-03-14 12:39:46'),
(51, 26, 'aqua_blue', '#4dd2ff', '2026-03-14 12:39:46'),
(52, 29, 'primary', '#214b54', '2026-03-14 14:17:29'),
(53, 29, 'primary_dark', '#152023', '2026-03-14 14:17:40'),
(54, 29, 'primary_light', '#8bc5d6', '2026-03-14 14:17:29'),
(55, 29, 'text', '#333333', '2026-03-14 14:17:29'),
(56, 29, 'text_light', '#666666', '2026-03-14 14:17:29'),
(57, 29, 'border', '#e0e0e0', '2026-03-14 14:17:29'),
(58, 29, 'success', '#28a745', '2026-03-14 14:17:29'),
(59, 29, 'danger', '#dc3545', '2026-03-14 14:17:29'),
(60, 29, 'warning', '#ffc107', '2026-03-14 14:17:29'),
(61, 29, 'info', '#17a2b8', '2026-03-14 14:17:29'),
(62, 29, 'coral', '#FF7F50', '2026-03-14 14:17:29'),
(63, 29, 'forest_green', '#2E7D32', '2026-03-14 14:17:29'),
(64, 29, 'lime_green', '#63E07E', '2026-03-14 14:17:29'),
(65, 29, 'sky_blue', '#66d9ff', '2026-03-14 14:17:29'),
(66, 29, 'aqua_blue', '#4dd2ff', '2026-03-14 14:17:29'),
(67, 32, 'primary', '#384d51', '2026-04-02 10:59:15'),
(68, 32, 'primary_dark', '#c7cfd1', '2026-04-02 10:59:15'),
(69, 32, 'primary_light', '#8bc5d6', '2026-04-01 22:23:59'),
(70, 32, 'text', '#333333', '2026-03-24 17:08:59'),
(71, 32, 'text_light', '#666666', '2026-03-24 17:08:59'),
(72, 32, 'border', '#e0e0e0', '2026-03-24 17:08:59'),
(73, 32, 'success', '#28a745', '2026-03-24 17:08:59'),
(74, 32, 'danger', '#dc3545', '2026-03-24 17:08:59'),
(75, 32, 'warning', '#ffc107', '2026-03-24 17:08:59'),
(76, 32, 'info', '#17a2b8', '2026-03-24 17:08:59'),
(77, 32, 'coral', '#FF7F50', '2026-03-24 17:08:59'),
(78, 32, 'forest_green', '#2E7D32', '2026-03-24 17:08:59'),
(79, 32, 'lime_green', '#63E07E', '2026-03-24 17:08:59'),
(80, 32, 'sky_blue', '#66d9ff', '2026-03-24 17:08:59'),
(81, 32, 'aqua_blue', '#4dd2ff', '2026-03-24 17:08:59'),
(82, 35, 'primary', '#66d9ff', '2026-03-27 10:21:24'),
(83, 35, 'primary_dark', '#4dd2ff', '2026-03-27 10:20:59'),
(84, 35, 'primary_light', '#80e5ff', '2026-03-27 10:20:59'),
(85, 35, 'text', '#333333', '2026-03-27 10:20:59'),
(86, 35, 'text_light', '#666666', '2026-03-27 10:20:59'),
(87, 35, 'border', '#e0e0e0', '2026-03-27 10:20:59'),
(88, 35, 'success', '#28a745', '2026-03-27 10:20:59'),
(89, 35, 'danger', '#dc3545', '2026-03-27 10:20:59'),
(90, 35, 'warning', '#ffc107', '2026-03-27 10:20:59'),
(91, 35, 'info', '#17a2b8', '2026-03-27 10:20:59'),
(92, 35, 'coral', '#FF7F50', '2026-03-27 10:20:59'),
(93, 35, 'forest_green', '#2E7D32', '2026-03-27 10:20:59'),
(94, 35, 'lime_green', '#63E07E', '2026-03-27 10:20:59'),
(95, 35, 'sky_blue', '#66d9ff', '2026-03-27 10:20:59'),
(96, 35, 'aqua_blue', '#4dd2ff', '2026-03-27 10:20:59'),
(97, 28, 'primary', '#dbe5a9', '2026-04-01 06:11:29'),
(98, 28, 'primary_dark', '#a4a871', '2026-04-01 06:11:29'),
(99, 28, 'primary_light', '#8bc5d6', '2026-04-01 06:11:02'),
(100, 28, 'text', '#333333', '2026-04-01 06:11:02'),
(101, 28, 'text_light', '#666666', '2026-04-01 06:11:02'),
(102, 28, 'border', '#e0e0e0', '2026-04-01 06:11:02'),
(103, 28, 'success', '#28a745', '2026-04-01 06:11:02'),
(104, 28, 'danger', '#dc3545', '2026-04-01 06:11:02'),
(105, 28, 'warning', '#ffc107', '2026-04-01 06:11:02'),
(106, 28, 'info', '#17a2b8', '2026-04-01 06:11:02'),
(107, 28, 'coral', '#FF7F50', '2026-04-01 06:11:02'),
(108, 28, 'forest_green', '#2E7D32', '2026-04-01 06:11:02'),
(109, 28, 'lime_green', '#63E07E', '2026-04-01 06:11:02'),
(110, 28, 'sky_blue', '#66d9ff', '2026-04-01 06:11:02'),
(111, 28, 'aqua_blue', '#4dd2ff', '2026-04-01 06:11:02');

-- --------------------------------------------------------

--
-- Table structure for table `tournaments`
--

CREATE TABLE `tournaments` (
  `id` int(11) NOT NULL,
  `tournament_name` varchar(100) NOT NULL,
  `game_type_id` int(11) NOT NULL,
  `season` varchar(20) DEFAULT NULL,
  `year` year(4) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `description` text DEFAULT NULL,
  `status` enum('Upcoming','Ongoing','Completed','Cancelled') DEFAULT 'Upcoming',
  `is_archived` tinyint(1) DEFAULT 0,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `tournaments`
--

INSERT INTO `tournaments` (`id`, `tournament_name`, `game_type_id`, `season`, `year`, `start_date`, `end_date`, `description`, `status`, `is_archived`, `created_by`, `created_at`, `updated_at`) VALUES
(4, 'Mbuzi cup 2026', 1, '2026', '2026', '2026-04-01', '2026-04-11', '', 'Upcoming', 0, 32, '2026-03-31 19:06:34', '2026-03-31 19:06:34'),
(6, 'Mbuzi cup 2026 net', 2, '2026', '2026', '2026-04-01', '2026-04-24', '', 'Upcoming', 0, 32, '2026-04-01 09:47:23', '2026-04-01 09:47:23');

-- --------------------------------------------------------

--
-- Table structure for table `tournament_stages`
--

CREATE TABLE `tournament_stages` (
  `id` int(11) NOT NULL,
  `stage_name` varchar(50) NOT NULL,
  `stage_order` int(11) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `color_code` varchar(7) DEFAULT '#6c757d',
  `bg_color` varchar(7) DEFAULT '#e9ecef'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `tournament_stages`
--

INSERT INTO `tournament_stages` (`id`, `stage_name`, `stage_order`, `description`, `created_at`, `color_code`, `bg_color`) VALUES
(1, 'Group Stage', 1, 'Group stage matches', '2026-03-31 16:51:42', '#ffc107', '#fff3cd'),
(2, 'Quarter Finals', 2, 'Quarter final matches', '2026-03-31 16:51:42', '#fd7e14', '#fff0e6'),
(3, 'Semi Finals', 3, 'Semi final matches', '2026-03-31 16:51:42', '#20c997', '#d1f7e9'),
(4, 'Final', 4, 'Championship final match', '2026-03-31 16:51:42', '#dc3545', '#f8d7da'),
(5, '3rd Place Playoff', 5, 'Third place playoff match', '2026-03-31 16:51:42', '#6c757d', '#e9ecef');

-- --------------------------------------------------------

--
-- Table structure for table `tournament_teams`
--

CREATE TABLE `tournament_teams` (
  `id` int(11) NOT NULL,
  `tournament_id` int(11) NOT NULL,
  `team_id` int(11) NOT NULL,
  `group_name` varchar(10) DEFAULT NULL,
  `points` int(11) DEFAULT 0,
  `matches_played` int(11) DEFAULT 0,
  `wins` int(11) DEFAULT 0,
  `draws` int(11) DEFAULT 0,
  `losses` int(11) DEFAULT 0,
  `goals_for` int(11) DEFAULT 0,
  `goals_against` int(11) DEFAULT 0,
  `goal_difference` int(11) DEFAULT 0,
  `status` enum('Active','Eliminated','Winner','RunnerUp') DEFAULT 'Active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `tournament_teams`
--

INSERT INTO `tournament_teams` (`id`, `tournament_id`, `team_id`, `group_name`, `points`, `matches_played`, `wins`, `draws`, `losses`, `goals_for`, `goals_against`, `goal_difference`, `status`, `created_at`) VALUES
(7, 4, 1, NULL, 1, 2, 0, 1, 1, 1, 3, -2, 'Active', '2026-03-31 19:07:06'),
(8, 4, 8, NULL, 2, 2, 0, 2, 0, 2, 2, 0, 'Active', '2026-03-31 19:07:06'),
(9, 4, 14, NULL, 0, 1, 0, 0, 1, 2, 4, -2, 'Active', '2026-03-31 19:25:49'),
(10, 4, 10, NULL, 6, 2, 2, 0, 0, 7, 4, 3, 'Active', '2026-03-31 19:25:49'),
(11, 4, 5, NULL, 6, 2, 2, 0, 0, 11, 3, 8, 'Active', '2026-04-01 06:06:31'),
(12, 4, 7, NULL, 0, 1, 0, 0, 1, 3, 9, -6, 'Active', '2026-04-01 06:06:31'),
(15, 4, 4, NULL, 0, 1, 0, 0, 1, 4, 5, -1, 'Active', '2026-04-01 09:36:51'),
(16, 4, 11, NULL, 3, 2, 1, 0, 1, 7, 7, 0, 'Active', '2026-04-01 09:36:51'),
(17, 4, 6, NULL, 1, 1, 0, 1, 0, 1, 1, 0, 'Active', '2026-04-01 12:13:38'),
(18, 6, 6, NULL, 0, 2, 0, 0, 2, 62, 76, -14, 'Active', '2026-04-01 12:31:12'),
(19, 6, 4, NULL, 3, 1, 1, 0, 0, 73, 60, 13, 'Active', '2026-04-01 12:31:12'),
(20, 6, 1, NULL, 3, 1, 1, 0, 0, 3, 2, 1, 'Active', '2026-04-01 13:41:46');

-- --------------------------------------------------------

--
-- Stand-in structure for view `unassigned_students_view`
-- (See below for the actual view)
--
CREATE TABLE `unassigned_students_view` (
`id` int(11)
,`index_number` varchar(50)
,`student_name` varchar(302)
,`sex` enum('Male','Female')
,`class` enum('Form Five','Form Six','Leavers','Graduated')
,`combination` enum('HGE','HGL','HGK','HKL','KLF','EGM','HLF','HGF')
,`is_leaver` tinyint(1)
,`student_status` tinyint(1)
);

-- --------------------------------------------------------

--
-- Table structure for table `user_preferences`
--

CREATE TABLE `user_preferences` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `preference_key` varchar(100) NOT NULL,
  `preference_value` text DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `user_preferences`
--

INSERT INTO `user_preferences` (`id`, `admin_id`, `preference_key`, `preference_value`, `updated_at`) VALUES
(8, 31, 'sidebar_collapsed', '1', '2026-03-14 10:57:47'),
(9, 31, 'font_size', '14', '2026-03-14 16:33:40'),
(10, 31, 'animations', '0', '2026-03-14 11:26:30'),
(11, 31, 'compact_mode', '0', '2026-03-13 23:15:03'),
(12, 31, 'show_icons', '1', '2026-03-13 23:16:33'),
(13, 31, 'background_opacity', '92', '2026-03-14 16:44:43'),
(14, 31, 'header_fixed', '1', '2026-03-14 08:12:34'),
(15, 14, 'sidebar_collapsed', '0', '2026-03-14 08:34:06'),
(16, 14, 'font_size', '12', '2026-04-02 07:26:57'),
(17, 14, 'animations', '0', '2026-03-14 08:34:06'),
(18, 14, 'compact_mode', '0', '2026-03-14 08:34:06'),
(19, 14, 'show_icons', '0', '2026-03-14 09:15:21'),
(20, 14, 'background_opacity', '100', '2026-03-14 08:34:06'),
(21, 14, 'header_fixed', '0', '2026-03-14 08:34:06'),
(22, 14, 'font_family', 'Segoe UI', '2026-03-14 08:39:48'),
(23, 14, 'animation_speed', 'normal', '2026-03-14 08:39:48'),
(24, 14, 'language', 'en', '2026-03-14 08:39:48'),
(25, 14, 'custom_css', '', '2026-03-14 08:39:48'),
(26, 31, 'font_family', 'Segoe UI', '2026-03-14 08:40:34'),
(27, 31, 'animation_speed', 'fast', '2026-03-14 10:57:47'),
(28, 31, 'language', '0', '2026-03-14 08:40:34'),
(29, 31, 'custom_css', '', '2026-03-14 08:40:34'),
(30, 14, 'background_option', 'image', '2026-03-14 12:47:19'),
(31, 31, 'background_option', 'image', '2026-03-14 12:16:45'),
(32, 26, 'sidebar_collapsed', '0', '2026-03-14 12:39:46'),
(33, 26, 'font_size', '18', '2026-03-14 13:12:01'),
(34, 26, 'animations', '0', '2026-03-14 12:39:46'),
(35, 26, 'compact_mode', '0', '2026-03-14 12:39:46'),
(36, 26, 'background_opacity', '60', '2026-03-14 13:12:17'),
(37, 26, 'background_option', 'milk', '2026-03-14 13:12:41'),
(38, 26, 'animation_speed', 'normal', '2026-03-14 12:39:46'),
(39, 29, 'sidebar_collapsed', '0', '2026-03-14 14:17:29'),
(40, 29, 'font_size', '16', '2026-03-14 14:17:29'),
(41, 29, 'animations', '0', '2026-03-14 14:17:29'),
(42, 29, 'compact_mode', '0', '2026-03-14 14:17:29'),
(43, 29, 'background_opacity', '65', '2026-03-14 14:17:29'),
(44, 29, 'background_option', 'image', '2026-03-14 14:29:34'),
(45, 29, 'animation_speed', 'normal', '2026-03-14 14:17:29'),
(46, 32, 'sidebar_collapsed', '0', '2026-03-26 05:31:27'),
(47, 32, 'font_size', '14', '2026-04-03 04:06:14'),
(48, 32, 'animations', '1', '2026-03-26 05:22:29'),
(49, 32, 'compact_mode', '0', '2026-03-24 17:08:59'),
(50, 32, 'background_opacity', '58', '2026-04-01 22:25:16'),
(51, 32, 'background_option', 'gray', '2026-04-02 10:59:32'),
(52, 32, 'animation_speed', 'fast', '2026-03-26 05:22:29'),
(53, 35, 'sidebar_collapsed', '0', '2026-03-27 10:20:59'),
(54, 35, 'font_size', '16', '2026-03-27 10:20:59'),
(55, 35, 'animations', '0', '2026-03-27 10:20:59'),
(56, 35, 'compact_mode', '0', '2026-03-27 10:20:59'),
(57, 35, 'background_opacity', '65', '2026-03-27 10:20:59'),
(58, 35, 'background_option', 'image', '2026-03-27 10:20:59'),
(59, 35, 'animation_speed', 'normal', '2026-03-27 10:20:59'),
(60, 28, 'sidebar_collapsed', '0', '2026-04-01 06:11:02'),
(61, 28, 'font_size', '16', '2026-04-01 06:11:02'),
(62, 28, 'animations', '0', '2026-04-01 06:11:02'),
(63, 28, 'compact_mode', '0', '2026-04-01 06:11:02'),
(64, 28, 'background_opacity', '65', '2026-04-01 06:11:02'),
(65, 28, 'background_option', 'milk', '2026-04-01 06:11:02'),
(66, 28, 'animation_speed', 'normal', '2026-04-01 06:11:02');

-- --------------------------------------------------------

--
-- Structure for view `dormitory_occupancy_summary`
--
DROP TABLE IF EXISTS `dormitory_occupancy_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `dormitory_occupancy_summary`  AS SELECT `d`.`id` AS `id`, `d`.`dorm_name` AS `dorm_name`, `d`.`dorm_type` AS `dorm_type`, `d`.`rooms_count` AS `rooms_count`, `d`.`capacity_per_room` AS `capacity_per_room`, `d`.`total_capacity` AS `total_capacity`, `d`.`current_occupancy` AS `current_occupancy`, greatest(`d`.`total_capacity` - `d`.`current_occupancy`,0) AS `available_beds`, round(`d`.`current_occupancy` * 100.0 / nullif(`d`.`total_capacity`,0),2) AS `occupancy_percentage`, `d`.`status` AS `dormitory_status`, `d`.`description` AS `description`, count(distinct `dr`.`id`) AS `total_rooms`, count(distinct case when `dr`.`status` = 'Available' then `dr`.`id` end) AS `available_rooms`, count(distinct case when `dr`.`status` = 'Full' then `dr`.`id` end) AS `full_rooms`, count(distinct case when `dr`.`status` = 'Maintenance' then `dr`.`id` end) AS `maintenance_rooms`, (select count(distinct `sd`.`id`) from (`student_dormitory` `sd` join `students` `s` on(`sd`.`student_id` = `s`.`id`)) where `sd`.`dormitory_id` = `d`.`id` and `sd`.`status` = 'Active' and `s`.`is_leaver` = 0 and `s`.`class` in ('Form Five','Form Six')) AS `active_student_count` FROM (`dormitories` `d` left join `dormitory_rooms` `dr` on(`d`.`id` = `dr`.`dormitory_id`)) GROUP BY `d`.`id`, `d`.`dorm_name`, `d`.`dorm_type`, `d`.`rooms_count`, `d`.`capacity_per_room`, `d`.`total_capacity`, `d`.`current_occupancy`, `d`.`status`, `d`.`description` ORDER BY `d`.`dorm_type` ASC, `d`.`dorm_name` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `room_availability_view`
--
DROP TABLE IF EXISTS `room_availability_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `room_availability_view`  AS SELECT `dr`.`id` AS `room_id`, `d`.`dorm_name` AS `dorm_name`, `d`.`dorm_type` AS `dorm_type`, `dr`.`room_number` AS `room_number`, `dr`.`room_label` AS `room_label`, `dr`.`capacity` AS `capacity`, `dr`.`current_occupancy` AS `current_occupancy`, greatest(`dr`.`capacity` - `dr`.`current_occupancy`,0) AS `available_beds`, `dr`.`status` AS `room_status`, `d`.`status` AS `dormitory_status`, CASE WHEN `dr`.`current_occupancy` = 0 THEN 'Empty' WHEN `dr`.`current_occupancy` < `dr`.`capacity` THEN 'Partially Occupied' WHEN `dr`.`current_occupancy` >= `dr`.`capacity` THEN 'Full' ELSE 'Unknown' END AS `occupancy_status`, (select count(0) from (`student_dormitory` `sd` join `students` `s` on(`sd`.`student_id` = `s`.`id`)) where `sd`.`room_id` = `dr`.`id` and `sd`.`status` = 'Active' and `s`.`is_leaver` = 0 and `s`.`class` in ('Form Five','Form Six')) AS `active_students_in_room`, `dr`.`created_at` AS `created_at`, `dr`.`updated_at` AS `updated_at` FROM (`dormitory_rooms` `dr` join `dormitories` `d` on(`dr`.`dormitory_id` = `d`.`id`)) WHERE `d`.`status` in ('Active','Full') ORDER BY `d`.`dorm_type` ASC, `d`.`dorm_name` ASC, cast(substr(`dr`.`room_number`,2) as unsigned) ASC, `dr`.`room_number` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `unassigned_students_view`
--
DROP TABLE IF EXISTS `unassigned_students_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `unassigned_students_view`  AS SELECT `s`.`id` AS `id`, `s`.`index_number` AS `index_number`, concat(`s`.`first_name`,' ',coalesce(`s`.`second_name`,''),' ',`s`.`last_name`) AS `student_name`, `s`.`sex` AS `sex`, `s`.`class` AS `class`, `s`.`combination` AS `combination`, `s`.`is_leaver` AS `is_leaver`, `s`.`status` AS `student_status` FROM `students` AS `s` WHERE `s`.`status` = 1 AND `s`.`is_leaver` = 0 AND !(`s`.`id` in (select `student_dormitory`.`student_id` from `student_dormitory` where `student_dormitory`.`status` = 'Active')) AND `s`.`class` in ('Form Five','Form Six') ORDER BY `s`.`sex` ASC, `s`.`class` ASC, `s`.`last_name` ASC, `s`.`first_name` ASC ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `admins`
--
ALTER TABLE `admins`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `admin_login_attempts`
--
ALTER TABLE `admin_login_attempts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_identifier` (`identifier`),
  ADD KEY `idx_attempt_time` (`attempt_time`);

--
-- Indexes for table `applications`
--
ALTER TABLE `applications`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `application_number` (`application_number`),
  ADD KEY `idx_application_number` (`application_number`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_program` (`program_applying`);

--
-- Indexes for table `dormitories`
--
ALTER TABLE `dormitories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `dorm_name` (`dorm_name`),
  ADD KEY `idx_dorm_type` (`dorm_type`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_dormitories_type_status` (`dorm_type`,`status`),
  ADD KEY `idx_dormitories_occupancy` (`current_occupancy`);

--
-- Indexes for table `dormitory_rooms`
--
ALTER TABLE `dormitory_rooms`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `dorm_room_unique` (`dormitory_id`,`room_number`),
  ADD KEY `dormitory_id` (`dormitory_id`),
  ADD KEY `idx_room_status` (`status`),
  ADD KEY `idx_room_number` (`room_number`),
  ADD KEY `idx_dormitory_rooms_dormitory_status` (`dormitory_id`,`status`),
  ADD KEY `idx_dormitory_rooms_occupancy` (`current_occupancy`,`capacity`),
  ADD KEY `idx_dormitory_rooms_number_status` (`room_number`,`status`);

--
-- Indexes for table `equipment_transactions`
--
ALTER TABLE `equipment_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `performed_by` (`performed_by`),
  ADD KEY `idx_equipment` (`equipment_id`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Indexes for table `exam_types`
--
ALTER TABLE `exam_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `exam_code` (`exam_code`);

--
-- Indexes for table `food_stock`
--
ALTER TABLE `food_stock`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `food_stock_history`
--
ALTER TABLE `food_stock_history`
  ADD PRIMARY KEY (`id`),
  ADD KEY `food_id` (`food_id`);

--
-- Indexes for table `form_five_results`
--
ALTER TABLE `form_five_results`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `exam_type_id` (`exam_type_id`);

--
-- Indexes for table `form_six_results`
--
ALTER TABLE `form_six_results`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_student_exam` (`student_id`,`exam_type_id`),
  ADD KEY `exam_type_id` (`exam_type_id`);

--
-- Indexes for table `game_types`
--
ALTER TABLE `game_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `game_name` (`game_name`);

--
-- Indexes for table `library_assignments`
--
ALTER TABLE `library_assignments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_type` (`user_type`),
  ADD KEY `idx_status` (`status`);

--
-- Indexes for table `maintenance_assignments`
--
ALTER TABLE `maintenance_assignments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `item_id` (`item_id`),
  ADD KEY `assigned_by` (`assigned_by`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_assigned_date` (`assigned_date`),
  ADD KEY `idx_return_date` (`return_date`);

--
-- Indexes for table `maintenance_items`
--
ALTER TABLE `maintenance_items`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `item_code` (`item_code`),
  ADD KEY `idx_item_type` (`item_type`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_location` (`location`);

--
-- Indexes for table `maintenance_logs`
--
ALTER TABLE `maintenance_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `item_id` (`item_id`),
  ADD KEY `admin_id` (`admin_id`),
  ADD KEY `idx_log_type` (`log_type`),
  ADD KEY `idx_user_type` (`user_type`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Indexes for table `maintenance_staff_assignments`
--
ALTER TABLE `maintenance_staff_assignments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `item_id` (`item_id`),
  ADD KEY `assigned_by` (`assigned_by`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_assigned_date` (`assigned_date`),
  ADD KEY `idx_return_date` (`return_date`);

--
-- Indexes for table `matches`
--
ALTER TABLE `matches`
  ADD PRIMARY KEY (`id`),
  ADD KEY `tournament_id` (`tournament_id`),
  ADD KEY `game_type_id` (`game_type_id`),
  ADD KEY `stage_id` (`stage_id`),
  ADD KEY `team1_id` (`team1_id`),
  ADD KEY `team2_id` (`team2_id`),
  ADD KEY `winner_team_id` (`winner_team_id`),
  ADD KEY `created_by` (`created_by`);

--
-- Indexes for table `matches_schedule`
--
ALTER TABLE `matches_schedule`
  ADD PRIMARY KEY (`id`),
  ADD KEY `tournament_id` (`tournament_id`),
  ADD KEY `stage_id` (`stage_id`),
  ADD KEY `team1_id` (`team1_id`),
  ADD KEY `team2_id` (`team2_id`);

--
-- Indexes for table `match_officials`
--
ALTER TABLE `match_officials`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_match_official` (`match_id`,`admin_id`,`role`),
  ADD KEY `admin_id` (`admin_id`);

--
-- Indexes for table `match_statistics`
--
ALTER TABLE `match_statistics`
  ADD PRIMARY KEY (`id`),
  ADD KEY `team_id` (`team_id`),
  ADD KEY `idx_match_id` (`match_id`);

--
-- Indexes for table `password_resets`
--
ALTER TABLE `password_resets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_token` (`token`),
  ADD KEY `idx_user` (`user_type`,`user_id`),
  ADD KEY `idx_expiry` (`expires_at`);

--
-- Indexes for table `productions`
--
ALTER TABLE `productions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_production_category` (`category`),
  ADD KEY `idx_production_date` (`production_date`);

--
-- Indexes for table `production_categories`
--
ALTER TABLE `production_categories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `category_name` (`category_name`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_category_status` (`status`);

--
-- Indexes for table `production_logs`
--
ALTER TABLE `production_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `production_id` (`production_id`),
  ADD KEY `admin_id` (`admin_id`);

--
-- Indexes for table `production_uses`
--
ALTER TABLE `production_uses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `production_id` (`production_id`),
  ADD KEY `created_by` (`created_by`);

--
-- Indexes for table `ps_documents`
--
ALTER TABLE `ps_documents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_uploaded_by` (`uploaded_by`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_file_type` (`file_type`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_ps_status` (`ps_status`),
  ADD KEY `idx_needs_review` (`needs_ps_review`);

--
-- Indexes for table `ps_document_feedback`
--
ALTER TABLE `ps_document_feedback`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_document_id` (`document_id`),
  ADD KEY `idx_commenter` (`commenter_id`),
  ADD KEY `idx_parent` (`parent_comment_id`);

--
-- Indexes for table `ps_document_logs`
--
ALTER TABLE `ps_document_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_document_id` (`document_id`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_action` (`action`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Indexes for table `ps_notifications`
--
ALTER TABLE `ps_notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_target_role` (`target_role`),
  ADD KEY `idx_document_id` (`document_id`),
  ADD KEY `idx_status` (`status`);

--
-- Indexes for table `results_auto_save`
--
ALTER TABLE `results_auto_save`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_session` (`session_id`),
  ADD KEY `idx_student_exam` (`student_id`,`exam_type_id`);

--
-- Indexes for table `results_entry_sessions`
--
ALTER TABLE `results_entry_sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_active` (`is_active`),
  ADD KEY `exam_type_id` (`exam_type_id`);

--
-- Indexes for table `room_status_logs`
--
ALTER TABLE `room_status_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `room_id` (`room_id`),
  ADD KEY `changed_by` (`changed_by`),
  ADD KEY `idx_changed_at` (`changed_at`),
  ADD KEY `idx_room_status_logs_room_date` (`room_id`,`changed_at`);

--
-- Indexes for table `sms_logs`
--
ALTER TABLE `sms_logs`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `sports_equipment`
--
ALTER TABLE `sports_equipment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_category` (`category`),
  ADD KEY `idx_quantity` (`quantity`);

--
-- Indexes for table `sports_history`
--
ALTER TABLE `sports_history`
  ADD PRIMARY KEY (`id`),
  ADD KEY `tournament_id` (`tournament_id`),
  ADD KEY `archived_by` (`archived_by`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_students_name` (`first_name`,`last_name`),
  ADD KEY `idx_students_parent` (`parent_phone`);

--
-- Indexes for table `student_dormitory`
--
ALTER TABLE `student_dormitory`
  ADD PRIMARY KEY (`id`),
  ADD KEY `dormitory_id` (`dormitory_id`),
  ADD KEY `room_id` (`room_id`),
  ADD KEY `assigned_by` (`assigned_by`),
  ADD KEY `idx_assignment_status` (`status`),
  ADD KEY `idx_student_dormitory_student_status` (`student_id`,`status`),
  ADD KEY `idx_student_dormitory_dormitory_status` (`dormitory_id`,`status`),
  ADD KEY `idx_student_dormitory_room_status` (`room_id`,`status`),
  ADD KEY `idx_student_dormitory_assigned_at` (`assigned_at`),
  ADD KEY `idx_student_dormitory_bed_number` (`bed_number`),
  ADD KEY `idx_student_status` (`student_id`,`status`);

--
-- Indexes for table `student_login_attempts`
--
ALTER TABLE `student_login_attempts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_identifier` (`identifier`),
  ADD KEY `idx_attempt_time` (`attempt_time`);

--
-- Indexes for table `student_login_logs`
--
ALTER TABLE `student_login_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_student_id` (`student_id`);

--
-- Indexes for table `subject_result_entry_log`
--
ALTER TABLE `subject_result_entry_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `teacher_id` (`teacher_id`),
  ADD KEY `exam_type_id` (`exam_type_id`);

--
-- Indexes for table `subject_teacher_assignments`
--
ALTER TABLE `subject_teacher_assignments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_assignment` (`teacher_id`,`subject`,`form_level`,`academic_year`),
  ADD KEY `assigned_by` (`assigned_by`);

--
-- Indexes for table `support_messages`
--
ALTER TABLE `support_messages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_user_type` (`user_type`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_assigned_to` (`assigned_to`);

--
-- Indexes for table `support_replies`
--
ALTER TABLE `support_replies`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_message_id` (`message_id`),
  ADD KEY `idx_reply_by` (`reply_by`);

--
-- Indexes for table `teams`
--
ALTER TABLE `teams`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_combination_team` (`team_type`,`combination_code`);

--
-- Indexes for table `team_participants`
--
ALTER TABLE `team_participants`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_participant` (`team_id`,`participant_type`,`participant_id`);

--
-- Indexes for table `theme_settings`
--
ALTER TABLE `theme_settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_admin_setting` (`admin_id`,`setting_key`);

--
-- Indexes for table `tournaments`
--
ALTER TABLE `tournaments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `game_type_id` (`game_type_id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_year` (`year`),
  ADD KEY `idx_is_archived` (`is_archived`);

--
-- Indexes for table `tournament_stages`
--
ALTER TABLE `tournament_stages`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `stage_name` (`stage_name`);

--
-- Indexes for table `tournament_teams`
--
ALTER TABLE `tournament_teams`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_tournament_team` (`tournament_id`,`team_id`),
  ADD KEY `team_id` (`team_id`);

--
-- Indexes for table `user_preferences`
--
ALTER TABLE `user_preferences`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_admin_preference` (`admin_id`,`preference_key`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `admins`
--
ALTER TABLE `admins`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT for table `admin_login_attempts`
--
ALTER TABLE `admin_login_attempts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=189;

--
-- AUTO_INCREMENT for table `applications`
--
ALTER TABLE `applications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `dormitories`
--
ALTER TABLE `dormitories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `dormitory_rooms`
--
ALTER TABLE `dormitory_rooms`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=123;

--
-- AUTO_INCREMENT for table `equipment_transactions`
--
ALTER TABLE `equipment_transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `exam_types`
--
ALTER TABLE `exam_types`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `food_stock`
--
ALTER TABLE `food_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28;

--
-- AUTO_INCREMENT for table `food_stock_history`
--
ALTER TABLE `food_stock_history`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `form_five_results`
--
ALTER TABLE `form_five_results`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=67;

--
-- AUTO_INCREMENT for table `form_six_results`
--
ALTER TABLE `form_six_results`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT for table `game_types`
--
ALTER TABLE `game_types`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `library_assignments`
--
ALTER TABLE `library_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `maintenance_assignments`
--
ALTER TABLE `maintenance_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `maintenance_items`
--
ALTER TABLE `maintenance_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `maintenance_logs`
--
ALTER TABLE `maintenance_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=39;

--
-- AUTO_INCREMENT for table `maintenance_staff_assignments`
--
ALTER TABLE `maintenance_staff_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `matches`
--
ALTER TABLE `matches`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28;

--
-- AUTO_INCREMENT for table `matches_schedule`
--
ALTER TABLE `matches_schedule`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `match_officials`
--
ALTER TABLE `match_officials`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `match_statistics`
--
ALTER TABLE `match_statistics`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `password_resets`
--
ALTER TABLE `password_resets`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=42;

--
-- AUTO_INCREMENT for table `productions`
--
ALTER TABLE `productions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `production_categories`
--
ALTER TABLE `production_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `production_logs`
--
ALTER TABLE `production_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `production_uses`
--
ALTER TABLE `production_uses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `ps_documents`
--
ALTER TABLE `ps_documents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `ps_document_feedback`
--
ALTER TABLE `ps_document_feedback`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `ps_document_logs`
--
ALTER TABLE `ps_document_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `ps_notifications`
--
ALTER TABLE `ps_notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `results_auto_save`
--
ALTER TABLE `results_auto_save`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `results_entry_sessions`
--
ALTER TABLE `results_entry_sessions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `room_status_logs`
--
ALTER TABLE `room_status_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `sms_logs`
--
ALTER TABLE `sms_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `sports_equipment`
--
ALTER TABLE `sports_equipment`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `sports_history`
--
ALTER TABLE `sports_history`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students`
--
ALTER TABLE `students`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=410;

--
-- AUTO_INCREMENT for table `student_dormitory`
--
ALTER TABLE `student_dormitory`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=61;

--
-- AUTO_INCREMENT for table `student_login_attempts`
--
ALTER TABLE `student_login_attempts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=61;

--
-- AUTO_INCREMENT for table `student_login_logs`
--
ALTER TABLE `student_login_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT for table `subject_result_entry_log`
--
ALTER TABLE `subject_result_entry_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `subject_teacher_assignments`
--
ALTER TABLE `subject_teacher_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `support_messages`
--
ALTER TABLE `support_messages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `support_replies`
--
ALTER TABLE `support_replies`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `teams`
--
ALTER TABLE `teams`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT for table `team_participants`
--
ALTER TABLE `team_participants`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `theme_settings`
--
ALTER TABLE `theme_settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=112;

--
-- AUTO_INCREMENT for table `tournaments`
--
ALTER TABLE `tournaments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `tournament_stages`
--
ALTER TABLE `tournament_stages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `tournament_teams`
--
ALTER TABLE `tournament_teams`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `user_preferences`
--
ALTER TABLE `user_preferences`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=67;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `dormitory_rooms`
--
ALTER TABLE `dormitory_rooms`
  ADD CONSTRAINT `dormitory_rooms_ibfk_1` FOREIGN KEY (`dormitory_id`) REFERENCES `dormitories` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `equipment_transactions`
--
ALTER TABLE `equipment_transactions`
  ADD CONSTRAINT `equipment_transactions_ibfk_1` FOREIGN KEY (`equipment_id`) REFERENCES `sports_equipment` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `equipment_transactions_ibfk_2` FOREIGN KEY (`performed_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `food_stock_history`
--
ALTER TABLE `food_stock_history`
  ADD CONSTRAINT `food_stock_history_ibfk_1` FOREIGN KEY (`food_id`) REFERENCES `food_stock` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `form_five_results`
--
ALTER TABLE `form_five_results`
  ADD CONSTRAINT `form_five_results_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `form_five_results_ibfk_2` FOREIGN KEY (`exam_type_id`) REFERENCES `exam_types` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `form_six_results`
--
ALTER TABLE `form_six_results`
  ADD CONSTRAINT `form_six_results_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `form_six_results_ibfk_2` FOREIGN KEY (`exam_type_id`) REFERENCES `exam_types` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `matches`
--
ALTER TABLE `matches`
  ADD CONSTRAINT `matches_ibfk_1` FOREIGN KEY (`tournament_id`) REFERENCES `tournaments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `matches_ibfk_2` FOREIGN KEY (`game_type_id`) REFERENCES `game_types` (`id`),
  ADD CONSTRAINT `matches_ibfk_3` FOREIGN KEY (`stage_id`) REFERENCES `tournament_stages` (`id`),
  ADD CONSTRAINT `matches_ibfk_4` FOREIGN KEY (`team1_id`) REFERENCES `teams` (`id`),
  ADD CONSTRAINT `matches_ibfk_5` FOREIGN KEY (`team2_id`) REFERENCES `teams` (`id`),
  ADD CONSTRAINT `matches_ibfk_6` FOREIGN KEY (`winner_team_id`) REFERENCES `teams` (`id`),
  ADD CONSTRAINT `matches_ibfk_7` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `matches_schedule`
--
ALTER TABLE `matches_schedule`
  ADD CONSTRAINT `matches_schedule_ibfk_1` FOREIGN KEY (`tournament_id`) REFERENCES `tournaments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `matches_schedule_ibfk_2` FOREIGN KEY (`stage_id`) REFERENCES `tournament_stages` (`id`),
  ADD CONSTRAINT `matches_schedule_ibfk_3` FOREIGN KEY (`team1_id`) REFERENCES `teams` (`id`),
  ADD CONSTRAINT `matches_schedule_ibfk_4` FOREIGN KEY (`team2_id`) REFERENCES `teams` (`id`);

--
-- Constraints for table `match_officials`
--
ALTER TABLE `match_officials`
  ADD CONSTRAINT `match_officials_ibfk_1` FOREIGN KEY (`match_id`) REFERENCES `matches` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `match_officials_ibfk_2` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`);

--
-- Constraints for table `match_statistics`
--
ALTER TABLE `match_statistics`
  ADD CONSTRAINT `match_statistics_ibfk_1` FOREIGN KEY (`match_id`) REFERENCES `matches` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `match_statistics_ibfk_2` FOREIGN KEY (`team_id`) REFERENCES `teams` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `productions`
--
ALTER TABLE `productions`
  ADD CONSTRAINT `productions_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `production_categories`
--
ALTER TABLE `production_categories`
  ADD CONSTRAINT `production_categories_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `production_logs`
--
ALTER TABLE `production_logs`
  ADD CONSTRAINT `production_logs_ibfk_1` FOREIGN KEY (`production_id`) REFERENCES `productions` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `production_logs_ibfk_2` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `production_uses`
--
ALTER TABLE `production_uses`
  ADD CONSTRAINT `production_uses_ibfk_1` FOREIGN KEY (`production_id`) REFERENCES `productions` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `production_uses_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ps_document_feedback`
--
ALTER TABLE `ps_document_feedback`
  ADD CONSTRAINT `fk_feedback_document` FOREIGN KEY (`document_id`) REFERENCES `ps_documents` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_feedback_parent` FOREIGN KEY (`parent_comment_id`) REFERENCES `ps_document_feedback` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ps_document_logs`
--
ALTER TABLE `ps_document_logs`
  ADD CONSTRAINT `fk_log_document` FOREIGN KEY (`document_id`) REFERENCES `ps_documents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ps_notifications`
--
ALTER TABLE `ps_notifications`
  ADD CONSTRAINT `fk_notification_document` FOREIGN KEY (`document_id`) REFERENCES `ps_documents` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `results_entry_sessions`
--
ALTER TABLE `results_entry_sessions`
  ADD CONSTRAINT `results_entry_sessions_ibfk_1` FOREIGN KEY (`exam_type_id`) REFERENCES `exam_types` (`id`);

--
-- Constraints for table `room_status_logs`
--
ALTER TABLE `room_status_logs`
  ADD CONSTRAINT `room_status_logs_ibfk_1` FOREIGN KEY (`room_id`) REFERENCES `dormitory_rooms` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `room_status_logs_ibfk_2` FOREIGN KEY (`changed_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `sports_equipment`
--
ALTER TABLE `sports_equipment`
  ADD CONSTRAINT `sports_equipment_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `sports_history`
--
ALTER TABLE `sports_history`
  ADD CONSTRAINT `sports_history_ibfk_1` FOREIGN KEY (`tournament_id`) REFERENCES `tournaments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `sports_history_ibfk_2` FOREIGN KEY (`archived_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `student_dormitory`
--
ALTER TABLE `student_dormitory`
  ADD CONSTRAINT `student_dormitory_ibfk_2` FOREIGN KEY (`dormitory_id`) REFERENCES `dormitories` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `student_dormitory_ibfk_3` FOREIGN KEY (`room_id`) REFERENCES `dormitory_rooms` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `student_dormitory_ibfk_4` FOREIGN KEY (`assigned_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `student_login_logs`
--
ALTER TABLE `student_login_logs`
  ADD CONSTRAINT `student_login_logs_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `subject_result_entry_log`
--
ALTER TABLE `subject_result_entry_log`
  ADD CONSTRAINT `subject_result_entry_log_ibfk_1` FOREIGN KEY (`teacher_id`) REFERENCES `admins` (`id`),
  ADD CONSTRAINT `subject_result_entry_log_ibfk_2` FOREIGN KEY (`exam_type_id`) REFERENCES `exam_types` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `subject_teacher_assignments`
--
ALTER TABLE `subject_teacher_assignments`
  ADD CONSTRAINT `subject_teacher_assignments_ibfk_1` FOREIGN KEY (`teacher_id`) REFERENCES `admins` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `subject_teacher_assignments_ibfk_2` FOREIGN KEY (`assigned_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `support_replies`
--
ALTER TABLE `support_replies`
  ADD CONSTRAINT `fk_reply_message` FOREIGN KEY (`message_id`) REFERENCES `support_messages` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `team_participants`
--
ALTER TABLE `team_participants`
  ADD CONSTRAINT `team_participants_ibfk_1` FOREIGN KEY (`team_id`) REFERENCES `teams` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `theme_settings`
--
ALTER TABLE `theme_settings`
  ADD CONSTRAINT `theme_settings_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `tournaments`
--
ALTER TABLE `tournaments`
  ADD CONSTRAINT `tournaments_ibfk_1` FOREIGN KEY (`game_type_id`) REFERENCES `game_types` (`id`),
  ADD CONSTRAINT `tournaments_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `tournament_teams`
--
ALTER TABLE `tournament_teams`
  ADD CONSTRAINT `tournament_teams_ibfk_1` FOREIGN KEY (`tournament_id`) REFERENCES `tournaments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `tournament_teams_ibfk_2` FOREIGN KEY (`team_id`) REFERENCES `teams` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `user_preferences`
--
ALTER TABLE `user_preferences`
  ADD CONSTRAINT `user_preferences_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
