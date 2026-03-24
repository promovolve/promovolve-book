(function() {
    // Determine current language from the URL path
    var path = window.location.pathname;
    var currentLang = path.indexOf('/ja/') !== -1 ? 'ja' : 'en';
    var otherLang = currentLang === 'en' ? 'ja' : 'en';
    var label = currentLang === 'en' ? '日本語' : 'English';

    // Build the toggle URL by swapping /en/ <-> /ja/
    var otherPath = path.replace('/' + currentLang + '/', '/' + otherLang + '/');

    // Create the toggle button
    var btn = document.createElement('a');
    btn.href = otherPath;
    btn.className = 'lang-toggle';
    btn.textContent = label;
    btn.title = currentLang === 'en' ? 'Switch to Japanese' : 'Switch to English';

    // Insert into the menu bar (right side icons area)
    var rightButtons = document.querySelector('.right-buttons');
    if (rightButtons) {
        rightButtons.insertBefore(btn, rightButtons.firstChild);
    }
})();
