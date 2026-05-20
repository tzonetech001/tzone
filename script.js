// script.js - tzone High School Main JavaScript

(function() {
    'use strict';
    
    // ==================== VISIT COUNT & DYNAMIC TIMING LOGIC ====================
    let storageKey = 'tzone_visit_count';
    let currentVisitCount = 0;
    
    try {
        let stored = localStorage.getItem(storageKey);
        if (stored !== null) {
            currentVisitCount = parseInt(stored, 10);
            if (isNaN(currentVisitCount)) currentVisitCount = 0;
        }
        // Increment for this visit
        let newCount = currentVisitCount + 1;
        localStorage.setItem(storageKey, newCount);
    } catch(e) {
        currentVisitCount = 0;
    }
    
    let previousCount = currentVisitCount;
    let loadDuration = 1000; // default 1 second
    
    // Dynamic timing based on visit count
    if (previousCount === 0) {
        loadDuration = 6000;   // First time: 6 seconds
    } else if (previousCount === 1) {
        loadDuration = 4000;   // Second time: 4 seconds
    } else if (previousCount === 2) {
        loadDuration = 2000;   // Third time: 2 seconds
    } else {
        loadDuration = 1000;   // Always 1 second after 3+ visits
    }
    
    // ==================== UPDATE LOADER MESSAGE ====================
    const loaderText = document.getElementById('loaderText');
    if (loaderText) {
        if (previousCount === 0) {
            loaderText.innerText = '✨ Welcome first time visitor! ✨';
        } else if (previousCount === 1) {
            loaderText.innerText = '🌟 Welcome back! 🌟';
        } else if (previousCount === 2) {
            loaderText.innerText = '⚡ Fast loading for you! ⚡';
        } else {
            loaderText.innerText = '🚀 Instant access! 🚀';
        }
    }
    
    // ==================== UPDATE LOADER DISPLAY WITH TIMER ====================
    const loaderTitle = document.querySelector('.loader-title');
    if (loaderTitle) {
        console.log(`Visit #${previousCount + 1} - Loading for ${loadDuration / 1000} seconds`);
    }
    
    // ==================== REDIRECT FUNCTION ====================
    const redirectTarget = "mhs/";
    
    function performRedirect() {
        const loader = document.getElementById('loaderScreen');
        if (loader) {
            loader.style.opacity = '0';
            setTimeout(() => {
                window.location.href = redirectTarget;
            }, 400);
        } else {
            window.location.href = redirectTarget;
        }
    }
    
    // ==================== REDIRECT AFTER DYNAMIC DURATION ====================
    let redirectTimer = setTimeout(performRedirect, loadDuration);
    
    // ==================== MANUAL LINK HANDLER ====================
    const manualLink = document.getElementById('manualLink');
    if (manualLink) {
        manualLink.addEventListener('click', function(e) {
            e.preventDefault();
            clearTimeout(redirectTimer);
            performRedirect();
        });
    }
    
    // ==================== EMERGENCY FALLBACK REDIRECT ====================
    setTimeout(function() {
        if (document.getElementById('loaderScreen') && window.location.pathname === '/') {
            window.location.href = redirectTarget;
        }
    }, loadDuration + 2000);
    
   
  
    
    // ==================== CONSOLE LOG FOR DEBUGGING ====================
    console.log(`tzone High School - Visit #${previousCount + 1} | Loading: ${loadDuration / 1000}s | Redirecting to: ${redirectTarget}`);
    
    // ==================== SMOOTH SCROLL FOR LINKS ====================
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            const href = this.getAttribute('href');
            if (href !== "#" && href !== "#seoContent") {
                return;
            }
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({ behavior: 'smooth' });
            }
        });
    });
    
})();