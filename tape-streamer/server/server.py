import asyncio
import aiofiles
import os
import random
import itertools
import uuid
import time
import json
import logging

import functools
import aiohttp.web
import aioredis

from chunker import Chunker

logging.basicConfig(level=logging.DEBUG)
logging.getLogger("asyncio").setLevel(logging.DEBUG)

HOST = os.getenv('HOST', '0.0.0.0')
PORT = int(os.getenv('PORT', 5000))

loop = asyncio.get_event_loop()

class WSView(aiohttp.web.View):
    def __init__(self, *args, **kwargs):
        self.drives = []
        self.drive_index = 0

        self.got_ack = False
        self.chunker = Chunker(server=True)

        self.ws = None
        self.redis = None

        super().__init__(*args, **kwargs)

    @property
    def latest_drive(self):
        if not self.drives:
            return None

        drive_id = self.drives[self.drive_index]
        self.drive_index += 1
        if self.drive_index >= len(self.drives):
            self.drive_index = 0

        return drive_id

    async def send(self, data):
        await self.ws.send_str(json.dumps(data))

    async def get(self):
        ws = aiohttp.web.WebSocketResponse(heartbeat=2)    
        print('Opening a socket.')

        await ws.prepare(self.request)
        print('Websocket connection ready')

        self.got_ack = True
        self.ws = ws
        self.redis = await aioredis.create_redis_pool(
            'redis://localhost',
            minsize=1,
            maxsize=4,
            loop=loop
        )

        async for message in self.ws:
            if message.type != aiohttp.WSMsgType.TEXT:
                continue

            print(f"{message.data}; chunk: {self.chunker.current_chunk}; drive: {self.drive_index}; ack: {self.got_ack}; {len(self.drives)} drives")
            await self.handle_message(message)

        print('Websocket connection closed')

        if self.redis:
            self.redis.close()
            await self.redis.wait_closed()
            print('Redis closed')

        return self.ws

    async def handle_message(self, message):
        data = json.loads(message.data)

        if data["cmd"] == 'close':
            await self.ws.close()
        elif data["cmd"] == "ack":
            self.got_ack = True
        elif data["cmd"] == "setchunk":
            self.chunker.set_chunk(data["i"])
        elif data["cmd"] == "ping":
            if not self.drives:
                await self.send({
                    "cmd": "getinfo"
                })
                return

            if not self.got_ack:
                return

            self.got_ack = False

            await self.send({
                "cmd": "getchunk",
                "chunk_id": self.chunker.current_chunk,
                "address": self.latest_drive
            })
            self.chunker.next_chunk()
        elif data["cmd"] == "drives":
            self.drives = data["drives"]

async def chunk_handler(request):
    chunk_i = int(request.match_info['chunk_i'])

    print(f"Sending chunk i {len(chunk)}")

    return aiohttp.web.Response(body=chunk)

def main():
    app = aiohttp.web.Application(loop=loop)
    app.router.add_view('/', WSView)
    app.router.add_static('/chunk/', "audio/")
    aiohttp.web.run_app(app, host=HOST, port=PORT)


if __name__ == '__main__':
    main()