# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

import sys
import traceback
from http import HTTPStatus
from aiohttp import web
from aiohttp.web import Request, Response, json_response
from botbuilder.core import (
    ActivityHandler,
    TurnContext
)
from botbuilder.integration.aiohttp import CloudAdapter
from botbuilder.schema import Activity

# Catch-all for errors.
async def on_error(context: TurnContext, error: Exception):
    print(f"\n [on_turn_error] unhandled error: {error}", file=sys.stderr)
    traceback.print_exc()

    # Send a message to the user
    await context.send_activity("The bot encountered an error or bug.")
    await context.send_activity(
        "To continue to run this bot, please fix the bot source code."
    )
    await context.send_activity(str(error))

def messages_routes(adapter: CloudAdapter, bot: ActivityHandler):
    # Listen for incoming requests on /api/messages.
    async def messages(req: Request) -> Response:
        # Parse incoming request
        if "application/json" in req.headers["Content-Type"]:
            body = await req.json()
        else:
            return Response(status=HTTPStatus.UNSUPPORTED_MEDIA_TYPE)
        activity = Activity().deserialize(body)
        auth_header = req.headers["Authorization"] if "Authorization" in req.headers else ""

        # Route received a request to adapter for processing
        response = await adapter.process_activity(auth_header, activity, bot.on_turn)
        if response:
            return json_response(data=response.body, status=response.status)
        return Response(status=HTTPStatus.OK)

    # Set the error handler on the Adapter.
    adapter.on_turn_error = on_error

    return [
        web.post("/api/messages", messages)
    ]