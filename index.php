<?php
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- PRIMARY SEO META TAGS -->
    <title>Tzone High School | Advanced Level Secondary School Kasulu Kigoma Tanzania</title>

    <!-- Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <!-- External CSS -->
    <link rel="stylesheet" href="style.css">
</head>
<body>


<!-- LOADER SCREEN (visible for dynamic seconds then fades) -->
<div id="loaderScreen" class="loader-screen">
    <div class="loader-card">
        <!-- Shaking Picture / Image -->
        <div class="shake-image">
            <img src="images/tzone.jpg" alt="Tzone High School" class="shaking-img" id="shakeImg" onerror="this.src='https://via.placeholder.com/100x100?text=MHS'">
        </div>
        
        <div class="loader-title">Tzone High School</div>
        <div class="loader-sub">Advanced Level | Education for life</div>
        
        <!-- BAR LOADER (vertical bars with animation) -->
        <div class="bar-loader">
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
        </div>
        
        <div class="loading-message" id="loaderText">
            Loading Tzone Experience...
        </div>
        
        <div class="redirect-link">
            <a href="mhs/" id="manualLink">If not redirected, click here →</a>
        </div>
    </div>
</div>

<!-- External JavaScript -->
<script src="script.js"></script>

<noscript>
    <meta http-equiv="refresh" content="6; url=mhs/">
    <div style="text-align:center; margin-top:100px; padding:20px;">
        <h2>Tzone High School</h2>
        <p>JavaScript is disabled. <a href="mhs/">Click here to continue →</a></p>
    </div>
</noscript>
</body>
</html>