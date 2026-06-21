import sys
import json
import urllib.request

def extract_page_title(url):
    try:
        with urllib.request.urlopen(url) as response:
            html_content = response.read().decode('utf-8')
            # Extract the title using a simple HTML parser
            import re
            title_match = re.search(r'<title>(.*?)</title>', html_content)
            if title_match:
                title = title_match.group(1)
                return {"ok": True, "tool": "extract_page_title", "title": title}
            else:
                return {"ok": False, "tool": "extract_page_title", "error": "No title found"}
    except urllib.error.URLError as e:
        return {"ok": False, "tool": "extract_page_title", "error": str(e)}
    except Exception as e:
        return {"ok": False, "tool": "extract_page_title", "error": str(e)}

def main():
    if len(sys.argv) != 2:
        print(json.dumps({"ok": False, "tool": "extract_page_title", "error": "Usage: python extract_page_title.py <URL>"}))
        return

    url = sys.argv[1]
    result = extract_page_title(url)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
