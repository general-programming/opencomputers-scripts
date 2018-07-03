import asyncio
import aiofiles
import os
import random
import itertools
import uuid
import subprocess
import time
import json
import logging

import functools
from concurrent.futures import ThreadPoolExecutor
import aiohttp.web

logging.basicConfig(level=logging.DEBUG)
logging.getLogger("asyncio").setLevel(logging.DEBUG)

HOST = os.getenv('HOST', '0.0.0.0')
PORT = int(os.getenv('PORT', 5000))
CHUNK_TIME = 5
global_state = {
    "songpath": "audio/default.opus"
}

thread_pool = ThreadPoolExecutor(max_workers=4)
loop = asyncio.get_event_loop()

def _chunk_file(filename, time_from, time_to):
    print(time_from, time_to)
    os.system("ffmpeg -y -i {filename} -ss {time_from} -to {time_to} -acodec pcm_s8 -f s8 -ac 1 -ar 96000 tmp.pcm".format(
        filename=filename,
        time_from=time_from,
        time_to=time_to
    ))

    with open("tmp.pcm", "rb") as tmp_pcm:
        process = subprocess.run(
            ["./aucmp"],
            stdout=subprocess.PIPE,
            input=tmp_pcm.read(),
            check=True
        )
        return process.stdout

class WSView(aiohttp.web.View):
    def __init__(self, *args, **kwargs):
        self.drives = []
        self.drive_index = 0

        self.got_ack = False
        self.chunk_index = 0

        self.ws = None

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

        async for message in self.ws:
            if message.type != aiohttp.WSMsgType.TEXT:
                continue

            print(f"{message.data}; chunk: {self.chunk_index}; drive: {self.drive_index}; ack: {self.got_ack}; {len(self.drives)} drives")
            await self.handle_message(message)

        print('Websocket connection closed')
        return self.ws

    async def handle_message(self, message):
        data = json.loads(message.data)

        if data["cmd"] == 'close':
            await self.ws.close()
        elif data["cmd"] == "ack":
            self.got_ack = True
        elif data["cmd"] == "setindex":
            self.chunk_index = data["i"]
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
                "chunk_i": self.chunk_index,
                "address": self.latest_drive
            })
            self.chunk_index += 1
        elif data["cmd"] == "drives":
            self.drives = data["drives"]

async def chunk_handler(request):
    chunk_i = int(request.match_info['chunk_i'])

    chunk = await loop.run_in_executor(
        thread_pool,
        functools.partial(_chunk_file, global_state["songpath"], CHUNK_TIME * chunk_i, CHUNK_TIME * (chunk_i + 1))
    )

    print(f"Sending chunk i {len(chunk)}")

    return aiohttp.web.Response(body=chunk)

def main():
    app = aiohttp.web.Application(loop=loop)
    app.router.add_view('/', WSView)
    app.router.add_get('/chunk/{chunk_i}', chunk_handler)
    aiohttp.web.run_app(app, host=HOST, port=PORT)


if __name__ == '__main__':
    main()