#!/usr/bin/env python3
"""Serveur de developpement, sans cache.

`python3 -m http.server` renvoie des 304 sur les modules : on edite un fichier,
on recharge, et le navigateur continue d'executer l'ancien. On perd alors du
temps a debugger du code qui n'est plus celui du disque.
"""

import sys
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path


class SansCache(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def send_header(self, keyword, value):
        # Un Last-Modified suffit au navigateur pour revalider et recevoir 304.
        if keyword == "Last-Modified":
            return
        super().send_header(keyword, value)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5173
    racine = Path(__file__).resolve().parent
    handler = partial(SansCache, directory=str(racine))
    print(f"hira web : http://127.0.0.1:{port}  (sans cache)")
    HTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    main()
