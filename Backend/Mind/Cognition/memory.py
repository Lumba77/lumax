import json
import os
import time
from typing import List, Optional

# Local fallback when Redis is offline: persisted reference stills (base64) per session.
_REF_IMAGE_FALLBACK_PATH = os.getenv("LUMAX_REF_IMAGE_FALLBACK_PATH", "lumax_reference_images.json")

import chromadb
import redis
from ollama import AsyncClient

from ollama_http import ollama_api_key

class ChatMessage:
    def __init__(self, role, content):
        self.role = role
        self.content = content

class ChatHistory:
    def __init__(self, messages):
        self.messages = messages

class RedisMemory:
    def __init__(self, host="localhost", port=6379):
        self.use_redis = True
        self.local_fallback_path = "sessions.json"
        try:
            self.redis_client = redis.Redis(
                host=host, port=port, socket_connect_timeout=1
            )
            self.redis_client.ping()
        except Exception:
            print("Redis not found. Falling back to local JSON memory (sessions.json).")
            self.use_redis = False
            if not os.path.exists(self.local_fallback_path):
                with open(self.local_fallback_path, "w") as f:
                    json.dump({}, f)

    def get(self, key):
        if self.use_redis:
            try:
                val = self.redis_client.get(key)
                return val.decode("utf-8") if val else None
            except Exception as e:
                print(f"Redis get error: {e}. Falling back to local.")
                # We don't set use_redis=False permanently here to allow for recovery,
                # but we proceed to local fallback for this call.
                pass
        
        if os.path.exists(self.local_fallback_path):
            try:
                with open(self.local_fallback_path, "r") as f:
                    data = json.load(f)
                    return data.get(key)
            except: pass
        return None

    def set(self, key, value):
        if self.use_redis:
            try:
                self.redis_client.setex(key, 3600, value)  # Expire after 1 hour
                return
            except Exception as e:
                print(f"Redis set error: {e}. Falling back to local.")
                pass

        try:
            data = {}
            if os.path.exists(self.local_fallback_path):
                with open(self.local_fallback_path, "r") as f:
                    data = json.load(f)
            data[key] = value
            with open(self.local_fallback_path, "w") as f:
                json.dump(data, f)
        except: pass

    async def get_session_history(self, session_id: str):
        data = self.get(f"session:{session_id}")
        if data:
            try:
                messages = json.loads(data)
                return ChatHistory([ChatMessage(m['role'], m['content']) for m in messages])
            except Exception:
                return ChatHistory([])
        return ChatHistory([])

    async def clear_session_history(self, session_id: str):
        if self.use_redis:
            self.redis_client.delete(f"session:{session_id}")
        else:
            with open(self.local_fallback_path, "r") as f:
                data = json.load(f)
            if f"session:{session_id}" in data:
                del data[f"session:{session_id}"]
            with open(self.local_fallback_path, "w") as f:
                json.dump(data, f)

    async def add_message_to_session(self, session_id: str, role: str, content: str):
        history = await self.get_session_history(session_id)
        messages = [{"role": m.role, "content": m.content} for m in history.messages]
        messages.append({"role": role, "content": content})
        self.set(f"session:{session_id}", json.dumps(messages))

    def get_session_summary(self, session_id: str) -> str:
        """Rolling dialogue spine (compressed summary), persisted per session."""
        raw = self.get(f"session_summary:{session_id}")
        return (raw or "").strip()

    def set_session_summary(self, session_id: str, text: str) -> None:
        """Persist summary with a long TTL (default 7d); separate from chat transcript keys."""
        ttl = int(os.getenv("LUMAX_SESSION_SUMMARY_TTL_SEC", "604800"))
        key = f"session_summary:{session_id}"
        text = (text or "").strip()
        if not text:
            return
        max_chars = int(os.getenv("LUMAX_SESSION_SUMMARY_STORE_MAX_CHARS", "16000"))
        if len(text) > max_chars:
            text = text[:max_chars] + "…"
        if self.use_redis:
            try:
                self.redis_client.setex(key, ttl, text)
                return
            except Exception as e:
                print(f"Redis set_session_summary error: {e}. Falling back to local.")
        try:
            data = {}
            if os.path.exists(self.local_fallback_path):
                with open(self.local_fallback_path, "r") as f:
                    data = json.load(f)
            data[key] = text
            with open(self.local_fallback_path, "w") as f:
                json.dump(data, f)
        except Exception as e:
            print(f"set_session_summary local fallback error: {e}")

    def _ref_redis_key(self, session_id: str) -> str:
        return f"lumax:ref_images:{session_id}"

    def _load_ref_fallback_store(self) -> dict:
        if not os.path.exists(_REF_IMAGE_FALLBACK_PATH):
            return {}
        try:
            with open(_REF_IMAGE_FALLBACK_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def _save_ref_fallback_store(self, data: dict) -> None:
        try:
            with open(_REF_IMAGE_FALLBACK_PATH, "w", encoding="utf-8") as f:
                json.dump(data, f)
        except Exception as e:
            print(f"Reference image fallback save error: {e}")

    async def push_reference_image(
        self,
        session_id: str,
        b64: str,
        max_items: Optional[int] = None,
        max_b64_len: Optional[int] = None,
    ) -> None:
        """Keep recent user / experience stills (base64) for img2img dreams and consolidation."""
        max_items = max_items if max_items is not None else int(os.getenv("LUMAX_REF_IMAGE_MAX", "12"))
        max_b64_len = max_b64_len if max_b64_len is not None else int(os.getenv("LUMAX_REF_IMAGE_MAX_B64", "480000"))
        ttl = int(os.getenv("LUMAX_REF_IMAGE_TTL_SEC", "1209600"))
        if not b64 or not isinstance(b64, str) or len(b64) < 64:
            return
        b64 = b64.strip()
        if len(b64) > max_b64_len:
            b64 = b64[:max_b64_len]
        key = self._ref_redis_key(session_id)
        if self.use_redis:
            try:
                self.redis_client.lpush(key, b64)
                self.redis_client.ltrim(key, 0, max(0, max_items - 1))
                self.redis_client.expire(key, ttl)
            except Exception as e:
                print(f"push_reference_image redis error: {e}")
            return
        store = self._load_ref_fallback_store()
        lst = store.get(session_id)
        if not isinstance(lst, list):
            lst = []
        lst.insert(0, b64)
        store[session_id] = lst[:max_items]
        self._save_ref_fallback_store(store)

    def get_reference_images(self, session_id: str, limit: int = 4) -> List[str]:
        """Newest first. Used as img2img inits for night dreams."""
        key = self._ref_redis_key(session_id)
        lim = max(1, min(int(limit), 24))
        if self.use_redis:
            try:
                raw = self.redis_client.lrange(key, 0, lim - 1)
                out = []
                for x in raw:
                    if isinstance(x, bytes):
                        x = x.decode("utf-8", errors="ignore")
                    if isinstance(x, str) and len(x) > 64:
                        out.append(x)
                return out
            except Exception as e:
                print(f"get_reference_images redis error: {e}")
                return []
        store = self._load_ref_fallback_store()
        lst = store.get(session_id)
        if not isinstance(lst, list):
            return []
        return [x for x in lst[:lim] if isinstance(x, str) and len(x) > 64]

class VectorMemory:
    def __init__(
        self,
        ollama_host: str,
        embed_model: str,
        collection_name: str = "experiential_long_term",
    ):
        _k = ollama_api_key()
        if _k:
            self.ollama_client = AsyncClient(
                host=ollama_host.rstrip("/"),
                headers={"Authorization": f"Bearer {_k}"},
            )
        else:
            self.ollama_client = AsyncClient(host=ollama_host.rstrip("/"))
        self.embed_model = embed_model
        self.chroma_client = chromadb.Client()
        
        # --- LAYERED COLLECTIONS ---
        # 1. Experiential (Long-Term events)
        self.long_term = self.chroma_client.get_or_create_collection("long_term")
        # 2. Lore (Refined foundational knowledge)
        self.lore_ledger = self.chroma_client.get_or_create_collection("lore_ledger")
        
        print(f"VectorMemory: Layered Architecture initialized (Long-Term & Lore).")

    async def refine_memory_layer(self, session_id: str, summary_text: str):
        """Allows Ratatosk to distill multiple experiential memories into a single Lore entry."""
        try:
            await self.add_memory(session_id, summary_text, collection="lore")
            print(f"Ratatosk: Distilled experience into foundational Lore for {session_id}.")
        except Exception as e:
            print(f"Memory Refinement Error: {e}")

    async def generate_embedding(self, text: str) -> list[float]:
        try:
            response = await self.ollama_client.embeddings(model=self.embed_model, prompt=text, keep_alive=0)
            return response["embedding"]
        except Exception as e:
            print(f"Error generating embedding: {e}")
            return []

    async def add_memory(self, session_id: str, text: str, metadata: dict = None, collection: str = "long_term"):
        try:
            embedding = await self.generate_embedding(text)
            if not embedding: return

            target = self.lore_ledger if collection == "lore" else self.long_term
            
            if metadata is None: metadata = {}
            metadata["session_id"] = session_id
            metadata["text"] = text
            metadata["layer"] = collection

            doc_id = f"{session_id}-{collection}-{hash(text)}-{time.time()}"

            target.add(
                embeddings=[embedding],
                documents=[text],
                metadatas=[metadata],
                ids=[doc_id],
            )
            print(f"Memory [{collection.upper()}] added for {session_id}: {text[:50]}...")
        except Exception as e:
            print(f"Error adding memory: {e}")

    async def retrieve_memories(
        self,
        session_id: str,
        query_text: str,
        n_results: int = 5,
        include_lore: bool = True,
        lore_n_results: int = 2,
    ) -> list[dict]:
        try:
            query_embedding = await self.generate_embedding(query_text)
            if not query_embedding: return []

            lore_k = max(0, int(lore_n_results))

            # 1. Search Long-Term Experiences
            results = self.long_term.query(
                query_embeddings=[query_embedding],
                n_results=n_results,
                where={"session_id": session_id},
                include=["documents", "metadatas", "distances"],
            )

            retrieved = []
            if results and results["documents"]:
                for i in range(len(results["documents"][0])):
                    retrieved.append({"text": results["documents"][0][i], "layer": "long_term", "dist": results["distances"][0][i]})

            # 2. Search Refined Lore (Priority Knowledge)
            if include_lore and lore_k > 0:
                lore_res = self.lore_ledger.query(
                    query_embeddings=[query_embedding],
                    n_results=lore_k,
                    where={"session_id": session_id},
                    include=["documents", "metadatas", "distances"],
                )
                if lore_res and lore_res["documents"]:
                    for i in range(len(lore_res["documents"][0])):
                        retrieved.append({"text": lore_res["documents"][0][i], "layer": "lore", "dist": lore_res["distances"][0][i]})

            # Sort by distance (relevance)
            retrieved.sort(key=lambda x: x["dist"])
            return retrieved[:n_results]
        except Exception as e:
            print(f"Error retrieving memories: {e}")
            return []

    def clear_session_memories(self, session_id: str):
        try:
            self.collection.delete(where={"session_id": session_id})
            print(f"Cleared all vector memories for session {session_id}.")
        except Exception as e:
            print(f"Error clearing session memories from ChromaDB: {e}")
