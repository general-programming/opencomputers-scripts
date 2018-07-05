import os
import glob
import redis
import subprocess
import json
import math
import tempfile
import asyncio
import functools
from concurrent.futures import ThreadPoolExecutor

loop = asyncio.get_event_loop()
thread_pool = ThreadPoolExecutor(max_workers=4)
r = redis.StrictRedis()
CHUNK_TIME = 5

def create_chunk(source_path: str, dest_path: str, chunk_i: int):
    process = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i", source_path,
            "-ss", str(CHUNK_TIME * chunk_i),
            "-to", str(CHUNK_TIME * (chunk_i + 1)),
            "-acodec", "pcm_s8",
            "-f", "s8",
            "-ac", "1",
            "-ar", "96000",
            dest_path
        ],
        stdout=subprocess.PIPE,
        check=True
    )

    return process.stdout

async def create_chunks(source_name, dest_name, chunk_count):
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Making PCMs for {source_name}")

        chunk_queue = []

        for chunk_i in range(0, chunk_count):
            chunk_task = loop.run_in_executor(
                thread_pool,
                functools.partial(
                    create_chunk,
                    source_name,
                    os.path.join(tmpdir, f"{dest_name}-{chunk_i}.pcm"),
                    chunk_i
                )
            )
            chunk_queue.append(chunk_task)
            if len(chunk_queue) > 8:
                await asyncio.gather(*chunk_queue)
                chunk_queue.clear()

        if len(chunk_queue) > 0:
            await asyncio.gather(*chunk_queue)

        print(f"Making DFPWMs for {source_name}")
        for chunk in glob.iglob(os.path.join(tmpdir, "*.pcm")):
            print(chunk)
            dfpwm_name = os.path.basename(chunk).split(".", 1)[0]
            with open(chunk, "rb") as tmp_pcm:
                process = subprocess.run(
                    ["./aucmp"],
                    stdout=subprocess.PIPE,
                    input=tmp_pcm.read(),
                    check=True
                )
                with open("audio/" + dfpwm_name, "wb") as chunk_dfpwm:
                    chunk_dfpwm.write(process.stdout)

def get_length(filename):
    process = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-i", filename],
        stdout=subprocess.PIPE,
        check=True
    )

    return float(json.loads(process.stdout)["format"]["duration"])

async def main():
    all_songs = {json.loads(x)["name"] for x in r.smembers("streamer:songs")}

    for filename in glob.iglob("unprocessed/*"):
        song_id = os.path.basename(filename).split(".", 1)[0]
        if song_id in all_songs:
            print("Skipped song that is already saved.")
            continue
        song_length = get_length(filename)
        chunk_count = int(math.ceil(song_length / 5.0))

        print(filename, get_length(filename))
        await create_chunks(filename, song_id, chunk_count)
        r.sadd("streamer:songs", json.dumps({
            "name": song_id,
            "length": song_length,
            "chunks": chunk_count
        }))

if __name__ == "__main__":
    loop.run_until_complete(main())