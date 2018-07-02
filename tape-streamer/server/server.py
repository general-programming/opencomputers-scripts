import asyncio
import aiofiles
import os
import random
import base64
import itertools
import uuid
import subprocess
import time
import json

import functools
from concurrent.futures import ThreadPoolExecutor
import aiohttp.web

HOST = os.getenv('HOST', '0.0.0.0')
PORT = int(os.getenv('PORT', 5000))
CHUNK_TIME = 5

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

async def websocket_handler(request):
    ws = aiohttp.web.WebSocketResponse()    
    print('Opening a socket.')

    await ws.prepare(request)
    print('Websocket connection ready')

    i = 0
    tape_index = 0
    acked = True
    drives = []

    async for msg in ws:
        print(f"{msg.data}; i: {i}; tape_i: {tape_index}; acked: {acked}; {len(drives)} drives")
        
        if msg.type != aiohttp.WSMsgType.TEXT:
            continue

        data = json.loads(msg.data)

        if data["cmd"] == 'close':
            await ws.close()
        elif data["cmd"] == "ack":
            acked = True
        elif data["cmd"] == "setindex":
            i = data["i"]
        elif data["cmd"] == "ping":
            if not drives:
                await ws.send_str(json.dumps({
                    "cmd": "getinfo"
                }))
                continue

            if not acked:
                continue

            acked = False

            await ws.send_str(json.dumps({
                "cmd": "getchunk",
                "chunk_i": i,
                "address": drives[tape_index]
            }))
            i += 1
            tape_index += 1
            if tape_index >= len(drives):
                tape_index = 0
        elif data["cmd"] == "drives":
            drives = data["drives"]

    print('Websocket connection closed')
    return ws

async def chunk_handler(request):
    chunk_i = int(request.match_info['chunk_i'])

    chunk = await loop.run_in_executor(
        thread_pool,
        functools.partial(_chunk_file, "doki.wav", CHUNK_TIME * chunk_i, CHUNK_TIME * (chunk_i + 1))
    )

    print(f"Sending chunk i {len(chunk)}")

    return aiohttp.web.Response(body=chunk)

def main():
    app = aiohttp.web.Application(loop=loop)
    app.router.add_get('/', websocket_handler)
    app.router.add_get('/chunk/{chunk_i}', chunk_handler)
    aiohttp.web.run_app(app, host=HOST, port=PORT)


if __name__ == '__main__':
    main()