/* Opt-in native urlencoded form recovery. The host owns policy; no page-specific fields. */
(function () {
    'use strict';
    window.KKJSBridgeInstallFormBodyRecovery = function (config) {
        if (!config || !config.scope || !Array.isArray(config.rules) || window.top !== window ||
            !('FormDataEvent' in window) || !window.KKJSBridge || !window.crypto ||
            window.__kkFormBodyRecoveryInstalled) return;
        var rules = config.rules.filter(function (r) {
            return location.origin === r.sourceOrigin && location.pathname.indexOf(r.sourcePathPrefix) === 0;
        });
        if (!rules.length) return;
        window.__kkFormBodyRecoveryInstalled = true;
        var pending = new WeakMap();
        var descriptors = Object.getOwnPropertyDescriptors(HTMLFormElement.prototype);
        var nativeEntries = FormData.prototype.forEach;
        function property(form, name) { return descriptors[name].get.call(form); }
        function effective(form, submitter, name, override) {
            return submitter && submitter.hasAttribute(override) ? submitter[override] : property(form, name);
        }
        function restore(state) {
            if (state.owner.getAttribute(state.attribute) === state.tagged) {
                if (state.original === null) state.owner.removeAttribute(state.attribute);
                else state.owner.setAttribute(state.attribute, state.original);
            }
        }
        window.addEventListener('submit', function (event) {
            var form = event.target;
            if (!(form instanceof HTMLFormElement) || !event.isTrusted || event.defaultPrevented ||
                !window.KKJSBridgeConfig || !window.KKJSBridgeConfig.ajaxHook) return;
            var submitter = event.submitter;
            var target = effective(form, submitter, 'target', 'formTarget');
            var action;
            try { action = new URL(effective(form, submitter, 'action', 'formAction'), document.baseURI); }
            catch (_) { return; }
            if (!rules.some(function (r) { return action.origin === r.targetOrigin && action.pathname === r.targetPath; }) ||
                action.username || action.password || action.href.indexOf('#') !== -1 ||
                effective(form, submitter, 'method', 'formMethod').toLowerCase() !== 'post' ||
                effective(form, submitter, 'enctype', 'formEnctype') !== 'application/x-www-form-urlencoded' ||
                (target && target.toLowerCase() !== '_self') || document.characterSet.toUpperCase() !== 'UTF-8' ||
                (property(form, 'acceptCharset') && property(form, 'acceptCharset').toUpperCase() !== 'UTF-8') ||
                (submitter && submitter.type === 'image') ||
                action.searchParams.has('KKJSBridge-RequestId') || action.searchParams.has('KKJSBridge-FormBody')) return;
            var controls = property(form, 'elements');
            for (var i = 0; i < controls.length; i++) {
                // _charset_ has special browser encoding semantics; custom elements may yield files.
                if (controls[i].type === 'file' || controls[i].name === '_charset_' ||
                    controls[i].localName.indexOf('-') !== -1 || controls[i].hasAttribute('dirname')) return;
            }
            var owner = submitter && submitter.hasAttribute('formaction') ? submitter : form;
            var attribute = owner === form ? 'action' : 'formaction';
            var random = new Uint8Array(16);
            crypto.getRandomValues(random);
            var id = config.scope + '.' + Array.from(random).map(function (v) { return ('0' + v.toString(16)).slice(-2); }).join('');
            var originalURL = action.href;
            // Do not serialize searchParams: that would change %20/+, escapes and signed queries.
            var tagged = originalURL + (originalURL.indexOf('?') === -1 ? '?' : '&') + 'KKJSBridge-FormBody=' + id;
            var state = { id: id, event: event, owner: owner, attribute: attribute,
                original: owner.getAttribute(attribute), tagged: tagged, url: originalURL, consumed: false };
            pending.set(form, state);
            owner.setAttribute(attribute, tagged);
            setTimeout(function () { restore(state); if (pending.get(form) === state) pending.delete(form); }, 0);
        });
        window.addEventListener('formdata', function (event) {
            var state = pending.get(event.target);
            // new FormData(form) within a submit listener is not the submission entry list.
            if (!state || state.consumed || state.event.defaultPrevented || state.event.eventPhase !== Event.NONE) return;
            state.consumed = true;
            var data = event.formData;
            // Run after all synchronous formdata listeners, including later window listeners.
            // Native holds the tagged request for at most two seconds; no synchronous prompt.
            setTimeout(function () {
                try {
                    var encoded = new URLSearchParams(), valid = true;
                    nativeEntries.call(data, function (value, key) {
                        if (typeof value !== 'string') { valid = false; return; }
                        encoded.append(key.replace(/\r\n|\r|\n/g, '\r\n'), value.replace(/\r\n|\r|\n/g, '\r\n'));
                    });
                    var body = encoded.toString();
                    if (!valid || body.length > 65536) return;
                    window.KKJSBridge.call('ajax', 'cacheFormBody', {
                        requestId: state.id, requestUrl: state.url, value: body
                    });
                } catch (_) { /* Missing cache is rejected by native; never send an empty replacement. */ }
            }, 0);
        });
    };
})();
