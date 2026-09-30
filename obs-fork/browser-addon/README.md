# Browser add-on patches / 浏览器组件补丁

These patch the `plugins/obs-browser` submodule (not the main OBS tree, which is
covered by `../patches`). Apply them inside the submodule:

```sh
cd obs-studio-clean/plugins/obs-browser
git apply ../../../obs-fork/browser-addon/0001-obs-browser-load-CEF-from-its-own-plugin-bundle.patch
```

`0001` lets obs-browser run as LiveHime's optional add-on: when its own bundle
contains `Contents/Frameworks/Chromium Embedded Framework.framework`, it

1. loads CEF from there instead of the app bundle;
2. sets `framework_dir_path`, `browser_subprocess_path` (the `OBS Helper` apps
   next to the framework) and `main_bundle_path` (the app, so child processes
   find the browser process);
3. starts CEF in `obs_module_post_load`, on the main thread, because LiveHime's
   frontend is built without the browser and never starts it;
4. uses English when the interface language is not among the CEF locales the
   add-on keeps (en, zh_CN, zh_TW).

Without such a bundle, behavior is unchanged. Verified in P0 and P1 (2026-09-30); see
`docs/BROWSER_ADDON_PLAN.md`.
