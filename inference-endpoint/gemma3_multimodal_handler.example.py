"""
Example Hugging Face Inference Endpoint handler for Gemma 3 (multimodal).

Uses the chat template and multimodal content blocks so image+text requests are not
flattened to a single string (which would mis-tokenize images and risk huge GPU allocations).

Requirements:
- Vision Gemma 3 instruct checkpoint, e.g. google/gemma-3-4b-it
- transformers >= 4.49 (Gemma 3 support)

The iOS app sends a curated facility list from GemmaFacilityAllowlist.json and expects one JSON
object for booking extraction (facilityCodes, gemmaInferenceExplanation, etc.) as defined in Swift.
"""

from __future__ import annotations

import gc
from typing import Any, Dict, List

import torch

torch.backends.cuda.enable_flash_sdp(False)
torch.backends.cuda.enable_mem_efficient_sdp(False)
torch.backends.cuda.enable_math_sdp(True)


def _clear_gpu_memory() -> None:
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        torch.cuda.synchronize()


def _unwrap_echo_inputs(messages: Any) -> List[Dict[str, Any]]:
    """Echo app: inputs = [[{role, content: [...]}]] or [{...}]."""
    if not messages:
        return []
    if isinstance(messages, list) and messages and isinstance(messages[0], list):
        raw_list = messages[0]
    else:
        raw_list = messages
    out: List[Dict[str, Any]] = []
    for msg in raw_list:
        if isinstance(msg, dict):
            out.append(msg)
    return out


def _content_parts_to_gemma(
    content: Any,
) -> List[Dict[str, Any]]:
    """
    Build Gemma 3 processor content blocks: {"type":"text"|"image", ...}
    Accepts OpenAI-style image_url or Gemma-style image url.
    """
    if isinstance(content, str):
        return [{"type": "text", "text": content}]

    if not isinstance(content, list):
        return [{"type": "text", "text": str(content)}]

    blocks: List[Dict[str, Any]] = []
    for part in content:
        if not isinstance(part, dict):
            blocks.append({"type": "text", "text": str(part)})
            continue

        ptype = part.get("type")

        if ptype == "text" or "text" in part:
            blocks.append({"type": "text", "text": str(part.get("text", ""))})
            continue

        if ptype == "image":
            url = part.get("url")
            if url:
                # Gemma 3 chat template (HF docs): {"type": "image", "url": "..."}
                # data:image/jpeg;base64,... is resolved by the processor in recent transformers.
                blocks.append({"type": "image", "url": str(url)})
            continue

        if ptype == "image_url":
            iu = part.get("image_url")
            url = iu.get("url") if isinstance(iu, dict) else iu
            if url:
                blocks.append({"type": "image", "url": str(url)})
            continue

        blocks.append({"type": "text", "text": str(part)})

    return [b for b in blocks if b.get("type") != "text" or str(b.get("text", "")).strip()]


def _echo_to_gemma_messages(inputs: Any) -> List[Dict[str, Any]]:
    gemma_messages: List[Dict[str, Any]] = []
    for msg in _unwrap_echo_inputs(inputs):
        role = msg.get("role") or "user"
        content = msg.get("content")
        if content is None:
            continue
        parts = _content_parts_to_gemma(content)
        if not parts:
            continue
        gemma_messages.append({"role": role, "content": parts})
    return gemma_messages


class EndpointHandler:
    def __init__(self, path: str = ""):
        self.path = path or "."
        self.processor = None
        self.model = None
        self._load_model()

    def _load_model(self) -> None:
        from transformers import AutoProcessor, Gemma3ForConditionalGeneration

        _clear_gpu_memory()
        model_path = self.path

        self.processor = AutoProcessor.from_pretrained(model_path, padding_side="left")
        self.model = Gemma3ForConditionalGeneration.from_pretrained(
            model_path,
            device_map="auto",
            torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        )
        _clear_gpu_memory()

    def __call__(self, data: Dict[str, Any]) -> List[Dict[str, str]]:
        inputs = data.pop("inputs", data)
        parameters = data.pop("parameters", None) or {}

        # Default 3000 max_new_tokens is dangerous for memory; keep inference small.
        max_new_tokens = min(int(parameters.get("max_new_tokens", 512)), 1024)
        max_new_tokens = max(max_new_tokens, 1)
        temperature = float(parameters.get("temperature", 0.2))
        top_p = float(parameters.get("top_p", 0.9))

        _clear_gpu_memory()
        try:
            messages = _echo_to_gemma_messages(inputs)
            if not messages:
                return [{"generated_text": "Error: no valid messages in inputs."}]

            model_inputs = self.processor.apply_chat_template(
                messages,
                tokenize=True,
                return_dict=True,
                return_tensors="pt",
                add_generation_prompt=True,
            )
            model_inputs = model_inputs.to(self.model.device)

            tok = self.processor.tokenizer
            pad_id = tok.pad_token_id or tok.eos_token_id

            gen_kwargs: Dict[str, Any] = {
                "max_new_tokens": max_new_tokens,
                "do_sample": temperature > 0.001,
                "temperature": temperature,
                "top_p": top_p,
                "pad_token_id": pad_id,
            }

            with torch.inference_mode():
                output_ids = self.model.generate(**model_inputs, **gen_kwargs)

            # Decode only new tokens (skip prompt)
            prompt_len = model_inputs["input_ids"].shape[1]
            generated = output_ids[0, prompt_len:]
            text = self.processor.decode(generated, skip_special_tokens=True).strip()
            return [{"generated_text": text}]
        finally:
            _clear_gpu_memory()
