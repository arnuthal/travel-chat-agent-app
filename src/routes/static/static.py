# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

from aiohttp import web
from aiohttp.web import FileResponse

def static_routes():
    return [
        web.get("/", lambda _: FileResponse("public/index.html")),
        web.static("/public", "public"),
    ]