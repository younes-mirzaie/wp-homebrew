# wp-homebrew

Signed catalog of homebrew apps for Windows Phone 8.1, read by **Unesbrews** (homebrew apps by Younes) on the phone.

- `apps/<id>.json`: one file per app (listing info + releases with URL, SHA-256, size).
- `dist/index.json` + `dist/index.json.sig`: the signed index GitHub Pages serves. Never edit by hand.
- `packages/`: the app packages, served by GitHub Pages (any other https URL works too; the SHA-256 pins them).

## Publishing a release

```
python catalog.py add Some_1.0.0.0_ARM.appx ^
    --url https://<owner>.github.io/wp-homebrew/packages/Some_1.0.0.0_ARM.appx ^
    --app-dir apps
REM fill in description, license, source, icon in apps\<id>.json
python catalog.py build --key <path-to-signing-key.pem> --app-dir apps --out dist
REM copy Some_1.0.0.0_ARM.appx into packages\
git add apps dist packages && git commit -m "Add Some 1.0.0.0" && git push
```

The signing key never goes in this repo or in CI. Its public half is built into Unesbrews.
Only list apps that may be redistributed.
