import json
import os

import chromadb
import redis
from ollama import AsyncClient

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

class VectorMemory:
    def __init__(
        self,
        ollama_host: str,
        embed_model: str,
        collection_name: str = "compagent_memories",
    ):
        self.ollama_client = AsyncClient(host=ollama_host)
        self.embed_model = embed_model

        # Initialize ChromaDB client
        # For a persistent client, you might specify a path: chromadb.PersistentClient(path="/path/to/db")
        # For simplicity, we'll start with an in-memory client.
        self.chroma_client = chromadb.Client()
        self.collection = self.chroma_client.get_or_create_collection(
            name=collection_name
        )
        print(f"VectorMemory initialized with ChromaDB collection: {collection_name}")

    async def generate_embedding(self, text: str) -> list[float]:
        try:
            response = await self.ollama_client.embeddings(
                model=self.embed_model, 
                prompt=text,
                keep_alive=0
            )
            return response["embedding"]
        except Exception as e:
            print(f"Error generating embedding with Ollama: {e}")
            return []

    async def add_memory(self, session_id: str, text: str, metadata: dict = None):
        try:
            embedding = await self.generate_embedding(text)
            if not embedding:
                print(
                    f"Could not generate embedding for text: {text}. Memory not added."
                )
                return

            if metadata is None:
                metadata = {}
            metadata["session_id"] = session_id
            metadata["text"] = text  # Store original text for retrieval

            # ChromaDB requires a unique ID for each document
            # await is not needed for collection.get or add yet as Chroma isn't fully async-native here but we are in an async def
            # We'll stick to the current logic but allow it to be awaited from outside.
            doc_id = f"{session_id}-{len(self.collection.get(where={'session_id': session_id}, include=[])['ids'])}-{hash(text)}"

            self.collection.add(
                embeddings=[embedding],
                documents=[text],
                metadatas=[metadata],
                ids=[doc_id],
            )
            print(f"Memory added for session {session_id}: {text[:50]}...")
        except Exception as e:
            print(f"Error adding memory to ChromaDB: {e}")

    async def retrieve_memories(
        self, session_id: str, query_text: str, n_results: int = 5
    ) -> list[dict]:
        try:
            query_embedding = await self.generate_embedding(query_text)
            if not query_embedding:
                return []

            results = self.collection.query(
                query_embeddings=[query_embedding],
                n_results=n_results,
                where={"session_id": session_id},
                include=["documents", "metadatas", "distances"],
            )

            # Format results
            retrieved_memories = []
            if results and results["documents"]:
                for i in range(len(results["documents"][0])):
                    retrieved_memories.append(
                        {
                            "text": results["documents"][0][i],
                            "metadata": results["metadatas"][0][i],
                            "distance": results["distances"][0][i],
                        }
                    )
            print(
                f"Retrieved {len(retrieved_memories)} memories for session {session_id} with query: {query_text[:50]}..."
            )
            return retrieved_memories
        except Exception as e:
            print(f"Error retrieving memories from ChromaDB: {e}")
            return []

    def clear_session_memories(self, session_id: str):
        try:
            self.collection.delete(where={"session_id": session_id})
            print(f"Cleared all vector memories for session {session_id}.")
        except Exception as e:
            print(f"Error clearing session memories from ChromaDB: {e}")
