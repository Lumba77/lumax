import os
import sys
import logging
from typing import Optional
import numpy as np
import torch

# Conditional imports
try:
    from llama_cpp import Llama
    GGUF_AVAILABLE = True
except ImportError:
    GGUF_AVAILABLE = False
    Llama = None  # type: ignore

try:
    from llama_cpp.llama_chat_format import Llava15ChatHandler
except ImportError:
    Llava15ChatHandler = None


def _env_bool(name: str, default: bool = False) -> bool:
    val = os.getenv(name, "").strip().lower()
    if not val:
        return default
    return val in ("1", "true", "yes", "on")

HF_AVAILABLE = False
try:
    from transformers import AutoTokenizer, AutoProcessor, AutoModelForCausalLM
    HF_AVAILABLE = True
except ImportError:
    AutoTokenizer = None
    AutoProcessor = None
    AutoModelForCausalLM = None

try:
    from transformers import AutoModelForVision2Seq
except ImportError:
    AutoModelForVision2Seq = None

class LumaxEngine:
    def __init__(self, model_path: str):
        self.model_path = model_path
        self.model_name = os.path.basename(model_path.rstrip("/"))
        self.engine_type = self._detect_type()
        self.model = None
        self.tokenizer = None
        self.processor = None
        # Set in load() when LUMAX_GGUF_NATIVE_VISION=1 and mmproj + Llava15ChatHandler init succeeds.
        self.gguf_multimodal_ready = False
        self.mmproj_path: Optional[str] = None
        # GGUF context window (supports long-context models if VRAM permits).
        try:
            ctx_raw = int(os.getenv("LUMAX_LOCAL_N_CTX", "32768") or "32768")
        except Exception:
            ctx_raw = 32768
        self.gguf_n_ctx = max(4096, min(ctx_raw, 65536))
        
        # Standard Settings
        self.gen_config = {
            "temperature": 0.7,
            "top_p": 0.8,
            "top_k": 20,
            "min_p": 0.0,
            "repetition_penalty": 1.18,
            "do_sample": True
        }
        
        logging.info(f"LumaxEngine: Init {self.engine_type} for {self.model_name}")

    def _detect_type(self):
        m_name = self.model_name.lower()
        
        # Check for GGUF files in the path (direct or inside dir)
        if self.model_path.endswith(".gguf"): return "GGUF"
        if os.path.isdir(self.model_path):
            for f in os.listdir(self.model_path):
                if f.endswith(".gguf"): return "GGUF"
            
            if "vl" in m_name: return "QWEN_VL"
            if "dflash" in m_name: return "DFLASH"
            if "gptq" in m_name or "awq" in m_name: return "QUANTIZED_HF"
            return "TRANSFORMERS"
        return "UNKNOWN"

    def _resolve_mmproj_path(self, model_file: str) -> Optional[str]:
        """mmproj path: LUMAX_MMPROJ_PATH, or *mmproj*.gguf next to weights / in model dir."""
        env_p = os.getenv("LUMAX_MMPROJ_PATH", "").strip()
        if env_p and os.path.isfile(env_p):
            return env_p
        search_dirs = []
        if os.path.isdir(self.model_path):
            search_dirs.append(self.model_path)
        else:
            parent = os.path.dirname(os.path.abspath(model_file))
            if os.path.isdir(parent):
                search_dirs.append(parent)
        for d in search_dirs:
            try:
                names = sorted(os.listdir(d))
            except OSError:
                continue
            for f in names:
                if f.endswith(".gguf") and "mmproj" in f.lower():
                    return os.path.join(d, f)
        return None

    def load(self):
        try:
            if self.engine_type == "GGUF" and GGUF_AVAILABLE:
                self.gguf_multimodal_ready = False
                self.mmproj_path = None
                model_file = self.model_path
                if os.path.isdir(self.model_path):
                    non_mm = sorted(
                        f
                        for f in os.listdir(self.model_path)
                        if f.endswith(".gguf") and "mmproj" not in f.lower()
                    )
                    if non_mm:
                        model_file = os.path.join(self.model_path, non_mm[0])

                mmproj_file = self._resolve_mmproj_path(model_file)
                self.mmproj_path = mmproj_file
                native_vision = _env_bool("LUMAX_GGUF_NATIVE_VISION", False)
                use_multimodal = bool(
                    mmproj_file
                    and native_vision
                    and Llava15ChatHandler is not None
                )

                logging.info(f"LumaxEngine: Manifesting GGUF Soul from {model_file}...")
                logging.info("LumaxEngine: GGUF n_ctx=%d", self.gguf_n_ctx)
                if use_multimodal:
                    logging.info(
                        "LumaxEngine: Native VL (experimental) — mmproj=%s, handler=Llava15ChatHandler",
                        mmproj_file,
                    )
                    try:
                        chat_handler = Llava15ChatHandler(clip_model_path=mmproj_file)  # type: ignore[misc]
                        self.model = Llama(
                            model_path=model_file,
                            chat_handler=chat_handler,
                            n_ctx=self.gguf_n_ctx,
                            n_gpu_layers=99,
                            flash_attn=False,
                        )
                        self.gguf_multimodal_ready = True
                    except Exception as mm_ex:
                        logging.warning(
                            "LumaxEngine: Native VL init failed (%s); loading text-only GGUF.",
                            mm_ex,
                        )
                        self.model = Llama(
                            model_path=model_file,
                            n_ctx=self.gguf_n_ctx,
                            n_gpu_layers=99,
                            flash_attn=False,
                        )
                else:
                    if mmproj_file and not native_vision:
                        logging.info(
                            "LumaxEngine: mmproj found at %s but LUMAX_GGUF_NATIVE_VISION is off — text-only load.",
                            mmproj_file,
                        )
                    self.model = Llama(
                        model_path=model_file,
                        n_ctx=self.gguf_n_ctx,
                        n_gpu_layers=99,
                        flash_attn=False,
                    )

                logging.info("LumaxEngine: GGUF Soul Manifested.")
                return True
            
            elif self.engine_type == "QWEN_VL" or self.engine_type == "QUANTIZED_HF":
                from transformers import AutoTokenizer, AutoModelForCausalLM
                logging.info(f"LumaxEngine: Manifesting {self.engine_type} Soul...")
                self.tokenizer = AutoTokenizer.from_pretrained(self.model_path, trust_remote_code=True)
                
                # Check for Flash Attention availability
                attn_impl = "eager"
                try:
                    import flash_attn
                    attn_impl = "flash_attention_2"
                    logging.info("LumaxEngine: Flash Attention 2 detected and enabled.")
                except ImportError:
                    logging.warning("LumaxEngine: Flash Attention not found, falling back to eager.")

                self.model = AutoModelForCausalLM.from_pretrained(
                    self.model_path, 
                    device_map="auto", 
                    torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
                    trust_remote_code=True,
                    attn_implementation=attn_impl
                )
                logging.info(f"LumaxEngine: {self.engine_type} Soul Manifested on {self.model.device}.")
                return True

            elif self.engine_type == "DFLASH":
                logging.info(f"LumaxEngine: Manifesting Qwen3.5-4B-DFlash Soul...")
                self.tokenizer = AutoTokenizer.from_pretrained(self.model_path, trust_remote_code=True)
                
                # Use importlib to load dflash.py directly to avoid sys.path pollution or naming conflicts
                dflash_path = os.path.join(self.model_path, "dflash.py")
                if os.path.exists(dflash_path):
                    import importlib.util
                    import sys
                    spec = importlib.util.spec_from_file_location("dflash_model", dflash_path)
                    dflash_mod = importlib.util.module_from_spec(spec)
                    sys.modules["dflash_model"] = dflash_mod
                    spec.loader.exec_module(dflash_mod)
                    
                    self.model = dflash_mod.DFlashDraftModel.from_pretrained(
                        self.model_path,
                        device_map="auto",
                        torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
                        trust_remote_code=True
                    )
                    logging.info("LumaxEngine: DFlash Soul Manifested (Block Diffusion Active).")
                    return True
                else:
                    logging.warning("dflash.py not found in model path, using transformers fallback...")
                    from transformers import AutoModelForCausalLM
                    
                    # Check for Flash Attention availability
                    attn_impl = "eager"
                    try:
                        import flash_attn
                        attn_impl = "flash_attention_2"
                    except ImportError:
                        pass

                    self.model = AutoModelForCausalLM.from_pretrained(
                        self.model_path,
                        device_map="auto",
                        torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
                        trust_remote_code=True,
                        attn_implementation=attn_impl
                    )
                    return True

            elif self.engine_type == "TRANSFORMERS":
                from transformers import AutoModelForCausalLM, BitsAndBytesConfig
                logging.info(f"LumaxEngine: Manifesting {self.model_name} with 4-bit optimization...")
                
                self.tokenizer = AutoTokenizer.from_pretrained(self.model_path, trust_remote_code=True)
                
                # 4-bit Quantization Config for RTX 4060 efficiency
                bnb_config = BitsAndBytesConfig(
                    load_in_4bit=True,
                    bnb_4bit_use_double_quant=True,
                    bnb_4bit_quant_type="nf4",
                    bnb_4bit_compute_dtype=torch.bfloat16
                )

                self.model = AutoModelForCausalLM.from_pretrained(
                    self.model_path,
                    quantization_config=bnb_config,
                    device_map="auto",
                    trust_remote_code=True
                )
                logging.info(f"LumaxEngine: Soul Manifested (4-bit Active).")
                return True
                
        except Exception as e:
            logging.error(f"LumaxEngine: Manifestation Failed -> {e}", exc_info=True)
        return False

    def generate(self, prompt: str, image_base64: str = None, max_tokens: int = 768) -> str:
        if not self.model: return "Soul not manifested."
        
        try:
            if self.engine_type == "GGUF":
                gguf_config = {
                    "temperature": self.gen_config.get("temperature", 0.7),
                    "top_p": self.gen_config.get("top_p", 0.8),
                    "top_k": self.gen_config.get("top_k", 20),
                    "repeat_penalty": self.gen_config.get("repetition_penalty", 1.1)
                }
                # Stops: do NOT use "\n\n" — it cuts off normal paragraphs after a few words.
                _stops = [
                    "USER:", "\nUSER:", "Daniel:", "\nDaniel:",
                    "<|eot_id|>", "<|end_of_text|>", "<|im_end|>", "<|im_end|>",
                ]
                if image_base64 and getattr(self, "gguf_multimodal_ready", False):
                    try:
                        raw_img = (image_base64 or "").strip()
                        if raw_img.startswith("data:"):
                            img_url = raw_img
                        else:
                            img_url = f"data:image/jpeg;base64,{raw_img}"
                        messages = [
                            {
                                "role": "user",
                                "content": [
                                    {"type": "image_url", "image_url": {"url": img_url}},
                                    {"type": "text", "text": prompt},
                                ],
                            }
                        ]
                        out = self.model.create_chat_completion(
                            messages=messages,
                            max_tokens=max_tokens,
                            stop=_stops,
                            temperature=gguf_config["temperature"],
                            top_p=gguf_config["top_p"],
                            top_k=gguf_config["top_k"],
                            repeat_penalty=gguf_config["repeat_penalty"],
                        )
                        ch0 = out["choices"][0]
                        msg = ch0.get("message") or {}
                        raw_c = msg.get("content")
                        if isinstance(raw_c, list):
                            piece = "".join(
                                x.get("text", "") if isinstance(x, dict) else str(x) for x in raw_c
                            ).strip()
                        elif isinstance(raw_c, str):
                            piece = raw_c.strip()
                        else:
                            piece = ""
                        if piece:
                            return piece
                    except Exception as mm_ex:
                        logging.warning(
                            "LumaxEngine: GGUF multimodal chat completion failed, falling back to text-only: %s",
                            mm_ex,
                        )
                output = self.model(prompt, max_tokens=max_tokens, stop=_stops, **gguf_config)
                return output["choices"][0]["text"].strip()

            elif (
                self.engine_type == "DFLASH"
                or self.engine_type == "TRANSFORMERS"
                or self.engine_type == "QUANTIZED_HF"
            ):
                # AWQ / GPTQ / plain HF text: vision is text-injected (compagent helper stack), not raw pixels here.
                inputs = self.tokenizer(prompt, return_tensors="pt").to(self.model.device)
                outputs = self.model.generate(**inputs, max_new_tokens=max_tokens, **self.gen_config)
                return self.tokenizer.decode(outputs[0], skip_special_tokens=True)

            else:
                # Qwen3-VL Logic
                content = [{"type": "text", "text": prompt}]
                if image_base64:
                    content.insert(0, {"type": "image", "image": f"data:image/jpeg;base64,{image_base64}"})
                
                messages = [{"role": "user", "content": content}]
                text = self.processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
                inputs = self.processor(text=[text], padding=True, return_tensors="pt").to(self.model.device)

                generated_ids = self.model.generate(**inputs, max_new_tokens=max_tokens)
                generated_ids_trimmed = [out_ids[len(in_ids):] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)]
                return self.processor.batch_decode(generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False)[0]
                
        except Exception as e:
            return f"Cognition Error: {e}"

    def generate_stream(self, prompt: str, max_tokens: int = 768):
        """Streams tokens word-by-word for GGUF models. Multimodal (native mmproj) is not wired here — use generate() with image_base64."""
        if not self.model or self.engine_type != "GGUF":
            yield "Soul not manifested or engine doesn't support streaming."
            return

        try:
            gguf_config = {
                "temperature": self.gen_config.get("temperature", 0.7),
                "top_p": self.gen_config.get("top_p", 0.8),
                "top_k": self.gen_config.get("top_k", 20),
                "repeat_penalty": self.gen_config.get("repetition_penalty", 1.1)
            }
            
            stream = self.model(
                prompt, 
                max_tokens=max_tokens, 
                stop=["USER:", "Daniel:", "<|im_end|>", "\n\n"], 
                stream=True,
                **gguf_config
            )
            
            for chunk in stream:
                if "choices" in chunk and len(chunk["choices"]) > 0:
                    text = chunk["choices"][0].get("text", "")
                    if text:
                        yield text
        except Exception as e:
            yield f" [Cognition Stream Error: {e}] "
