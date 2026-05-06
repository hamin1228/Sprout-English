# server/app/stt_pipeline.py
from __future__ import annotations
import io, json, math, os
from dataclasses import dataclass
from typing import List, Tuple, Dict, Any
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, resample_poly
import yaml
from rapidfuzz import fuzz

@dataclass
class Config:
    sample_rate: int
    channels: int
    hp_hz: int
    hp_order: int
    frame_ms: int
    hop_ms: int
    min_seg_ms: int
    silence_gap_ms: int
    rms_thresh_dbfs: float
    rms_percentile: float
    dict_enable: bool
    dict_max_distance: int
    dict_case_ins: bool
    join_short_seg_ms: int
    max_gap_merge_ms: int
    punct_merge: bool

def load_config(path: str) -> Config:
    with open(path, "r", encoding="utf-8") as f:
        y = yaml.safe_load(f)
    return Config(
        sample_rate=y["sample_rate"], channels=y["channels"],
        hp_hz=y["filter"]["highpass_hz"], hp_order=y["filter"]["order"],
        frame_ms=y["vad"]["frame_ms"], hop_ms=y["vad"]["hop_ms"],
        min_seg_ms=y["vad"]["min_seg_ms"], silence_gap_ms=y["vad"]["silence_gap_ms"],
        rms_thresh_dbfs=y["vad"]["rms_thresh_dbfs"], rms_percentile=y["vad"]["rms_percentile"],
        dict_enable=y["dictionary"]["enable"], dict_max_distance=y["dictionary"]["max_distance"],
        dict_case_ins=y["dictionary"]["case_insensitive"],
        join_short_seg_ms=y["sentence"]["join_short_seg_ms"],
        max_gap_merge_ms=y["sentence"]["max_gap_merge_ms"],
        punct_merge=y["sentence"]["punct_merge"],
    )

def load_dictionary(path: str) -> Dict[str, Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        j = json.load(f)
    d = {}
    for e in j.get("entries", []):
        term = e["term"]
        aliases = set([term]) | set(e.get("aliases", []))
        d[term] = {"aliases": list(aliases), "pronunciations": e.get("pronunciations", [])}
    return d

def read_audio(audio_bytes: bytes, target_sr: int, target_ch: int) -> Tuple[np.ndarray, int]:
    y, sr = sf.read(io.BytesIO(audio_bytes), always_2d=True)
    # to mono
    y = y.mean(axis=1)
    # resample if needed
    if sr != target_sr:
        # use polyphase
        g = math.gcd(sr, target_sr)
        y = resample_poly(y, target_sr // g, sr // g)
        sr = target_sr
    # clip
    y = np.clip(y, -1.0, 1.0).astype(np.float32)
    return y, sr

def highpass(y: np.ndarray, sr: int, cutoff_hz: int, order: int) -> np.ndarray:
    sos = butter(order, cutoff_hz / (sr / 2.0), btype="highpass", output="sos")
    return sosfilt(sos, y)

def rms_dbfs(x: np.ndarray) -> float:
    eps = 1e-9
    return 20 * np.log10(np.sqrt(np.mean(np.square(x))) + eps)

def frame_rms(y: np.ndarray, sr: int, frame_ms: int, hop_ms: int) -> Tuple[np.ndarray, int]:
    frame = int(sr * frame_ms / 1000)
    hop = int(sr * hop_ms / 1000)
    if frame <= 0: frame = 1
    if hop <= 0: hop = 1
    n = 1 + max(0, (len(y) - frame) // hop)
    rms = np.empty(n, dtype=np.float32)
    for i in range(n):
        s = i * hop
        e = s + frame
        rms[i] = np.sqrt(np.mean(y[s:e] ** 2) + 1e-9)
    return 20 * np.log10(rms + 1e-9), hop

def detect_segments(y: np.ndarray, sr: int, cfg: Config) -> List[Tuple[int, int]]:
    """Return list of (start_ms, end_ms) for speech segments separated by silence ≥ silence_gap_ms."""
    rms_db, hop = frame_rms(y, sr, cfg.frame_ms, cfg.hop_ms)
    # dynamic threshold: percentile + floor
    p = np.percentile(rms_db, cfg.rms_percentile * 100.0)
    thresh = max(p, cfg.rms_thresh_dbfs)
    # boolean speech mask
    speech = rms_db > thresh
    # find stretches of silence ≥ silence_gap
    gap_frames = int(cfg.silence_gap_ms / cfg.hop_ms)
    segs: List[Tuple[int, int]] = []
    start = 0
    i = 0
    # helper to convert frame index -> ms
    def f2ms(fr_idx: int) -> int:
        return int(fr_idx * cfg.hop_ms)
    # iterate and cut on long silent runs
    while i < len(speech):
        if not speech[i]:
            # count consecutive silence
            j = i
            while j < len(speech) and not speech[j]:
                j += 1
            if (j - i) >= gap_frames:
                end_ms = f2ms(i)
                if end_ms - f2ms(start) >= cfg.min_seg_ms:
                    segs.append((f2ms(start), end_ms))
                start = j
                i = j
                continue
            else:
                i = j
                continue
        i += 1
    # tail
    end_ms = f2ms(len(speech))
    if end_ms - f2ms(start) >= cfg.min_seg_ms:
        segs.append((f2ms(start), end_ms))
    # clamp to audio length
    total_ms = int(len(y) * 1000 / sr)
    segs = [(max(0, s), min(total_ms, e)) for s, e in segs if e > s]
    return segs

def whisper_stt(segment_audio: np.ndarray, sr: int) -> str:
    """
    Transcribe audio segment using OpenAI Whisper.
    Args:
        segment_audio: Audio data as numpy array
        sr: Sample rate
    Returns:
        Transcribed text
    """
    import tempfile
    import os
    from openai import OpenAI
    
    # numpy array를 WAV 파일로 저장
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        tmp_path = tmp.name
        sf.write(tmp_path, segment_audio, sr)
    
    try:
        client = OpenAI()
        model_name = (os.getenv("OPENAI_STT_PIPELINE_MODEL") or "").strip()
        if not model_name:
            return ""
        with open(tmp_path, 'rb') as f:
            response = client.audio.transcriptions.create(
                file=f,
                model=model_name,
                response_format='text'
            )
        return response.strip() if isinstance(response, str) else response.text.strip()
    except Exception as e:
        # 실패 시 빈 문자열 반환
        print(f"Whisper STT failed: {e}")
        return ""
    finally:
        # 임시 파일 삭제
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

def apply_dictionary(text: str, dictionary: Dict[str, Dict[str, Any]], max_dist: int, case_ins: bool) -> str:
    if not text.strip():
        return text
    tokens = text.split()
    def norm(w: str) -> str:
        return w.lower() if case_ins else w
    for i, w in enumerate(tokens):
        nw = norm(w)
        best = (0, w)
        for term, data in dictionary.items():
            for alias in data["aliases"]:
                score = fuzz.ratio(nw, norm(alias))
                if score > best[0]:
                    best = (score, term)
        # 허용 거리 체크(짧은 단어 위주)
        if best[0] >= 90:
            tokens[i] = best[1]
    return " ".join(tokens)

def merge_to_sentences(segments: List[Tuple[int, int]], texts: List[str], cfg: Config) -> List[Tuple[int, int, str, List[int]]]:
    out = []
    cur_s, cur_e = None, None
    cur_text = []
    cur_idxs = []
    for idx, (s, e) in enumerate(segments):
        t = texts[idx]
        if cur_s is None:
            cur_s, cur_e = s, e
            cur_text = [t]
            cur_idxs = [idx]
            continue
        gap = s - cur_e
        short_seg = (e - s) < cfg.join_short_seg_ms
        end_punct = "".join(cur_text).strip().endswith((".", "?", "!", ":", "。", "！", "？"))
        should_merge = (gap <= cfg.max_gap_merge_ms) or short_seg or (cfg.punct_merge and not end_punct)
        if should_merge and (e - cur_s) <= 10000:  # 10s cap
            cur_e = e
            cur_text.append(t)
            cur_idxs.append(idx)
        else:
            out.append((cur_s, cur_e, " ".join(x for x in cur_text if x), cur_idxs))
            cur_s, cur_e = s, e
            cur_text = [t]
            cur_idxs = [idx]
    if cur_s is not None:
        out.append((cur_s, cur_e, " ".join(x for x in cur_text if x), cur_idxs))
    # hard cap >10s
    final = []
    for (s, e, txt, idxs) in out:
        if (e - s) <= 10000:
            final.append((s, e, txt.strip(), idxs))
        else:
            mid = s + (e - s) // 2
            final.append((s, mid, txt.strip(), idxs[: len(idxs)//2 or 1]))
            final.append((mid, e, "", idxs[len(idxs)//2 or 1:]))
    return final

class STTPipeline:
    def __init__(self, cfg_path: str, dict_path: str | None):
        self.cfg_path = cfg_path
        self.dict_path = dict_path
        self.reload()

    def reload(self):
        self.cfg = load_config(self.cfg_path)
        self.dictionary = load_dictionary(self.dict_path) if self.dict_path else {}

    def run(self, audio_bytes: bytes) -> Dict[str, Any]:
        y, sr = read_audio(audio_bytes, self.cfg.sample_rate, self.cfg.channels)
        y = highpass(y, sr, self.cfg.hp_hz, self.cfg.hp_order)
        segs = detect_segments(y, sr, self.cfg)
        texts = []
        for (s_ms, e_ms) in segs:
            s = int(s_ms * sr / 1000)
            e = int(e_ms * sr / 1000)
            txt = whisper_stt(y[s:e], sr)
            if self.cfg.dict_enable and txt:
                txt = apply_dictionary(txt, self.dictionary, self.cfg.dict_max_distance, self.cfg.dict_case_ins)
            texts.append(txt)
        sents = merge_to_sentences(segs, texts, self.cfg)
        return {
            "sample_rate": sr,
            "segments": [
                {"idx": i, "start_ms": s, "end_ms": e, "duration_ms": e - s, "text": texts[i]}
                for i, (s, e) in enumerate(segs)
            ],
            "sentences": [
                {"idx": i, "start_ms": s, "end_ms": e, "duration_ms": e - s, "text": txt, "segments": idxs}
                for i, (s, e, txt, idxs) in enumerate(sents)
            ],
        }
