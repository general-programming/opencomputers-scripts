import redis
import random
import json


class Chunker(object):
    def __init__(self, server: bool=False):
        self.redis = redis.StrictRedis()
        self.current_song = None
        self.chunk_count = 0
        self.current_chunk_index = 0

        if server:
            self.random_song()

    def random_song(self):
        all_songs = [json.loads(x) for x in self.redis.smembers("streamer:songs")]
        song_pick = random.choice(all_songs)

        self.current_song = song_pick["name"]
        self.chunk_count = song_pick["chunks"]
        print("Picked random song", song_pick["name"])

    @property
    def current_chunk(self):
        return f"{self.current_song}-{self.current_chunk_index}"

    def set_chunk(self, chunk_id):
        print(f"Setting chunk to {chunk_id}")

        chunk_splits = chunk_id.split("-")

        if len(chunk_splits) != 2:
            print(f"too many splits? {chunk_id}")
            return

        all_songs = [json.loads(x) for x in r.smembers("streamer:songs")]

        self.current_song = chunk_splits[0]
        self.current_chunk_index = int(chunk_splits[1])
        for song in all_songs:
            if song["name"] == self.current_song:
                self.chunk_count = song["chunks"]
                return

        raise Exception(f"Could not find song {self.current_song} in memory.")

    def next_chunk(self):
        self.current_chunk_index += 1
        if self.current_chunk_index > self.chunk_count:
            self.current_chunk_index = 0
