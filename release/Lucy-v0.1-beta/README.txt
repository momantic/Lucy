Lucy v0.1 Beta

Setup:
1. Open Lucy.app.
2. Open Chrome > chrome://extensions.
3. Enable Developer Mode.
4. Load unpacked extension:
   browser_bridge/extension
5. Start browser bridge:
   python3 browser_bridge/server.py

LinkedIn drafting:
Ask Lucy:
"write me a linkedin post about ai agents in stock markets"

Privacy:
- Lucy runs locally.
- Browser bridge runs on localhost.
- Lucy reads browser page text only through the installed local extension.
- Lucy does not post to LinkedIn automatically.
