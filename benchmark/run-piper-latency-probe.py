import argparse
import json
import statistics
import time
import wave
from pathlib import Path

import onnxruntime as ort
from piper import PiperVoice
from piper.config import PiperConfig


TEXTS = {
    "short": "Olá! A Lia está pronta. Como posso ajudar?",
    "paragraph": (
        "Bom dia! Esta é uma amostra de português brasileiro para comparar a latência "
        "da voz. A Lia pode responder perguntas, ler números como vinte e quatro, "
        "explicar uma tarefa e continuar a conversa com clareza. Quando a resposta "
        "for curta, o primeiro áudio precisa começar rapidamente; em textos maiores, "
        "também importam a pronúncia, a naturalidade e a estabilidade da prosódia."
    ),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--provider", choices=("cpu", "directml"), required=True)
    parser.add_argument("--runs", type=int, default=4)
    args = parser.parse_args()

    model = Path(args.model).resolve()
    out_dir = Path(args.output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    requested = ["CPUExecutionProvider"] if args.provider == "cpu" else [
        "DmlExecutionProvider", "CPUExecutionProvider"
    ]
    profile_dir = out_dir / "ort-profile"
    profile_dir.mkdir(exist_ok=True)
    session_options = ort.SessionOptions()
    session_options.enable_profiling = True
    if args.provider == "directml":
        session_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        session_options.enable_mem_pattern = False
    session_options.profile_file_prefix = str(out_dir / "ort-profile" / f"ort-{args.provider}")
    started = time.perf_counter()
    session = ort.InferenceSession(
        str(model), sess_options=session_options, providers=requested
    )
    load_seconds = time.perf_counter() - started
    active_providers = session.get_providers()
    if args.provider == "directml" and "DmlExecutionProvider" not in active_providers:
        raise RuntimeError(
            "DirectML was requested but is not active; refusing to label a CPU fallback as GPU. "
            f"Active providers: {active_providers}"
        )

    with model.with_suffix(model.suffix + ".json").open("r", encoding="utf-8") as f:
        config = PiperConfig.from_dict(json.load(f))
    voice = PiperVoice(
        session=session,
        config=config,
        download_dir=model.parent,
    )

    results = {
        "providerRequested": requested,
        "providersActive": active_providers,
        "pythonOnnxRuntimeVersion": ort.__version__,
        "modelLoadSeconds": load_seconds,
        "sampleRate": config.sample_rate,
        "runsPerText": args.runs,
        "texts": {},
        "sessionProfile": None,
    }
    try:
        for label, text in TEXTS.items():
            # One untimed warm-up, then identical repetitions.
            list(voice.synthesize(text))
            first_chunk_seconds = []
            total_seconds = []
            audio_durations = []
            last_chunks = None
            for _ in range(args.runs):
                iterator = iter(voice.synthesize(text))
                t0 = time.perf_counter()
                try:
                    first = next(iterator)
                except StopIteration:
                    raise RuntimeError(f"Piper returned no audio for {label} sample")
                first_chunk_seconds.append(time.perf_counter() - t0)
                chunks = [first, *iterator]
                total_seconds.append(time.perf_counter() - t0)
                audio_durations.append(
                    sum(len(chunk.audio_float_array) for chunk in chunks) / config.sample_rate
                )
                last_chunks = chunks

            wav_path = out_dir / f"faber-{args.provider}-{label}.wav"
            with wave.open(str(wav_path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(config.sample_rate)
                wav_file.writeframes(b"".join(chunk.audio_int16_bytes for chunk in last_chunks))
            results["texts"][label] = {
                "firstAudioMedianSeconds": statistics.median(first_chunk_seconds),
                "totalMedianSeconds": statistics.median(total_seconds),
                "audioDurationSeconds": statistics.median(audio_durations),
                "realTimeFactorMedian": statistics.median(total_seconds)
                / max(statistics.median(audio_durations), 1e-9),
                "wav": wav_path.name,
            }
    finally:
        profile_path = session.end_profiling()

    try:
        events = json.loads(Path(profile_path).read_text(encoding="utf-8"))
        node_providers = sorted(
            {
                str(event.get("args", {}).get("provider"))
                for event in events
                if event.get("cat") == "Node" and event.get("args", {}).get("provider")
            }
        )
    except Exception as exc:
        node_providers = []
        results["profileParseError"] = type(exc).__name__
    results["nodeProvidersObserved"] = node_providers
    results["sessionProfile"] = Path(profile_path).name
    if args.provider == "directml" and "DmlExecutionProvider" not in node_providers:
        results["gpuExecutionConfirmed"] = False
        result_path = out_dir / f"piper-{args.provider}-result.json"
        result_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
        raise RuntimeError(
            "DirectML session was available, but no model nodes were confirmed on DML. "
            f"Observed node providers: {node_providers}. Result: {result_path}"
        )
    results["gpuExecutionConfirmed"] = (
        args.provider == "directml" and "DmlExecutionProvider" in node_providers
    )
    result_path = out_dir / f"piper-{args.provider}-result.json"
    result_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False))


if __name__ == "__main__":
    main()
