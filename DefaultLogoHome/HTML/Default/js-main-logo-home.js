/*
 * Only change the destination of the logo link in the Default skin.
 * Leave all other links and skins untouched.
 */
Ext.onReady(function () {
    var logo = document.getElementById('squeezeboxLogo');
    if (logo && logo.parentNode && logo.parentNode.tagName.toLowerCase() === 'a') {
        logo.parentNode.href = '/';
    }
});
