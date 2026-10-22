/*
 * Change only the Default skin's Lyrion logo link.
 * In HTML/Default/index.html the image is nested inside a span inside the link.
 */
Ext.onReady(function () {
    var logo = document.getElementById('squeezeboxLogo');
    if (!logo) {
        return;
    }

    var link = logo.parentNode;
    while (link && link.tagName && link.tagName.toLowerCase() !== 'a') {
        link = link.parentNode;
    }

    if (link && link.tagName && link.tagName.toLowerCase() === 'a') {
        link.href = '[% webroot %]';
    }
});
