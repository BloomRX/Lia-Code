# Cole este arquivo inteiro em UMA célula do Colab e execute.
# O teste é de inferência/clonagem, NÃO inicia fine-tuning.
# A gravação de referência fica no runtime Colab; não é enviada aos Spaces/demos.
# Modelos/pacotes ficam em /content/lia_tts_candidate_eval (fora do Git).

from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import textwrap
import time
import venv

# ---------- Configuração que pode ser alterada sem editar o restante ----------
ROOT = Path('/content/lia_tts_candidate_eval')
REF_WAV = ROOT / 'lia_original.wav'
# Corrija para a transcrição literal da gravação escolhida, se necessário.
REF_TEXT = 'Não é por vocês serem velhos e acabados.'
TEXTS = [
    'Não é por vocês serem velhos e acabados.',
    'O ônibus chegou às seis; vou passar no mercado e comprar pão de queijo.',
    'Você está falando sério? A gente se vê depois, tá bom?',
]

# Revisões fixas para que o teste seja repetível.
SPACE_ID = 'ResembleAI/Chatterbox-Multilingual-TTS-pt-br'
SPACE_REV = '9e515821e826e207cd617a0fdd0223899ed108ea'
CHATTERBOX_PTBR_ID = 'ResembleAI/Chatterbox-Multilingual-pt-br'
CHATTERBOX_PTBR_REV = 'b3952f18bc2eaa72b9bd7c17d2c4653bcad4770d'
CHATTERBOX_BASE_ID = 'ResembleAI/chatterbox'
CHATTERBOX_BASE_REV = '5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18'
QWEN_ID = 'Qwen/Qwen3-TTS-12Hz-0.6B-Base'
QWEN_REV = '5d83992436eae1d760afd27aff78a71d676296fc'

ROOT.mkdir(parents=True, exist_ok=True)
if shutil.disk_usage(ROOT).free < 15 * 1024**3:
    raise RuntimeError('Menos de 15 GiB livres em /content; libere espaço antes de baixar os dois candidatos.')
# Mantém cache de pesos e pip dentro do diretório removível do experimento.
CHILD_ENV = os.environ.copy()
CHILD_ENV['HF_HOME'] = str(ROOT / 'hf_home')
CHILD_ENV['PIP_CACHE_DIR'] = str(ROOT / 'pip_cache')
CHILD_ENV['TORCH_HOME'] = str(ROOT / 'torch_home')

# Confirma GPU antes de baixar vários GB ou instalar pacotes.
import torch
if not torch.cuda.is_available():
    raise RuntimeError('Este teste requer GPU CUDA ativa no Colab (preferência: T4). Não baixei modelos. Ative GPU e execute a célula novamente.')
print('GPU:', torch.cuda.get_device_name(0))
print('VRAM total: %.1f GiB' % (torch.cuda.get_device_properties(0).total_memory / 1024**3))
print('Torch existente:', torch.__version__, '| CUDA:', torch.version.cuda)

# Upload local privado ao runtime Colab; não usa referência de voz em API hospedada.
if not REF_WAV.exists():
    try:
        from google.colab import files
    except Exception as exc:
        raise RuntimeError('Execute no Colab ou coloque o WAV original em ' + str(REF_WAV)) from exc
    print('Envie o WAV ORIGINAL limpo da Lia (não o arquivo gerado).')
    uploaded = files.upload()
    if len(uploaded) != 1:
        raise ValueError('Envie exatamente um WAV original.')
    uploaded_name, uploaded_bytes = next(iter(uploaded.items()))
    if not uploaded_name.lower().endswith('.wav'):
        raise ValueError('A referência precisa ser WAV para este teste.')
    REF_WAV.write_bytes(uploaded_bytes)

# Confere duração e formato antes de iniciar downloads grandes.
import soundfile as sf
ref_audio, ref_sr = sf.read(str(REF_WAV), dtype='float32', always_2d=True)
ref_seconds = len(ref_audio) / ref_sr
print(f'Referência: {REF_WAV.name}; {ref_sr} Hz; {ref_seconds:.2f} s; {ref_audio.shape[1]} canal(is).')
if ref_seconds < 2.0:
    raise ValueError('Referência muito curta (<2 s). Escolha uma gravação limpa mais longa.')
if ref_seconds < 5.0:
    print('AVISO: referência abaixo de 5 s; a clonagem pode ficar menos estável. Se puder, use 6–15 s de fala limpa da mesma voz.')

# Venvs isolados com acesso ao Torch já instalado no Colab. Não substitui nem
# atualiza o ambiente principal de treino. Os modelos ficam apenas em /content.
def make_env(name, packages):
    env_dir = ROOT / ('venv-' + name)
    py = env_dir / 'bin' / 'python'
    if not py.exists() or not (env_dir / 'pyvenv.cfg').exists():
        if env_dir.exists():
            shutil.rmtree(env_dir)
        # Python 3.13 Colab may omit ensurepip; the runtime pip installs into this venv's target dir below.
        venv.EnvBuilder(with_pip=False, system_site_packages=True).create(str(env_dir))
    # Colab expõe pacotes em dist-packages; inclua explicitamente a pasta Torch
    # do kernel atual no venv, sem copiar nem alterar os pacotes globais.
    site_dirs = [p for p in sys.path if p and ('site-packages' in p or 'dist-packages' in p) and Path(p).is_dir()]
    venv_site = next((p for p in (env_dir / 'lib').glob('python*/site-packages')), None)
    if venv_site is None:
        raise RuntimeError('Não encontrei site-packages no ambiente isolado ' + str(env_dir))
    if site_dirs:
        (venv_site / 'colab_kernel_paths.pth').write_text('\n'.join(dict.fromkeys(site_dirs)) + '\n', encoding='utf-8')
    marker = env_dir / '.lia_deps_ready'
    if not marker.exists():
        cmd = [sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check',
              '--no-warn-script-location', '--upgrade', '--target', str(venv_site), *packages]
        subprocess.run(cmd, check=True, env=CHILD_ENV)
        marker.write_text('ok\n', encoding='utf-8')
    return py

# ---------- Chatterbox: pack PT-BR dedicado + referência da Lia ----------
chat_py = make_env('chatterbox_ptbr', [
    'numpy>=2.1,<2.4', 'resampy==0.4.3', 'librosa==0.11.0', 's3tokenizer',
    'transformers==4.46.3', 'diffusers==0.29.0', 'omegaconf==2.3.0',
    'resemble-perth==1.0.1', 'silero-vad==5.1.2', 'conformer==0.3.2',
    'safetensors', 'huggingface_hub==0.30.2',
])

space_dir = ROOT / 'chatterbox_ptbr_space'
if not space_dir.exists():
    subprocess.run(['git', 'clone', 'https://huggingface.co/spaces/' + SPACE_ID, str(space_dir)], check=True, env=CHILD_ENV)
subprocess.run(['git', '-C', str(space_dir), 'fetch', '--all'], check=True, env=CHILD_ENV)
subprocess.run(['git', '-C', str(space_dir), 'checkout', '--force', SPACE_REV], check=True, env=CHILD_ENV)

chat_runner = ROOT / 'run_chatterbox_ptbr.py'
chat_runner.write_text(textwrap.dedent(r'''
    import json, sys, time
    from pathlib import Path
    import numpy as np
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download

    root = Path(sys.argv[1]); space_dir = Path(sys.argv[2])
    ref_path = Path(sys.argv[3]); texts = json.loads(Path(sys.argv[4]).read_text(encoding='utf-8'))
    sys.path.insert(0, str(space_dir))
    from chatterbox.src.chatterbox.tts import ChatterboxTTS

    assets = root / 'chatterbox_ptbr_assets'
    assets.mkdir(parents=True, exist_ok=True)
    base = Path(snapshot_download(
        repo_id='ResembleAI/chatterbox',
        revision='5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18',
        allow_patterns=['ve.pt', 'conds.pt'],
    ))
    ptbr = Path(snapshot_download(
        repo_id='ResembleAI/Chatterbox-Multilingual-pt-br',
        revision='b3952f18bc2eaa72b9bd7c17d2c4653bcad4770d',
        allow_patterns=['t3_pt_br.safetensors', 's3gen_v3.pt', 'grapheme_mtl_merged_expanded_v1.json'],
    ))
    for name, folder in [
        ('ve.pt', base), ('conds.pt', base),
        ('t3_pt_br.safetensors', ptbr), ('s3gen_v3.pt', ptbr),
        ('grapheme_mtl_merged_expanded_v1.json', ptbr),
    ]:
        target = assets / name
        if not target.exists():
            target.symlink_to(folder / name)

    t0 = time.perf_counter()
    model = ChatterboxTTS.from_local(str(assets), device='cuda')
    load_s = time.perf_counter() - t0
    print(f'Chatterbox PT-BR carregado em {load_s:.2f}s; sample rate={model.sr}.')
    model.prepare_conditionals(str(ref_path), exaggeration=0.5)
    rows = []
    for i, text in enumerate(texts, 1):
        torch.manual_seed(1234)
        t0 = time.perf_counter()
        wav = model.generate(text, language_id='pt', exaggeration=0.5, temperature=0.8, cfg_weight=0.5)
        elapsed = time.perf_counter() - t0
        arr = wav.squeeze().detach().float().cpu().numpy() if torch.is_tensor(wav) else np.asarray(wav).squeeze()
        path = root / f'chatterbox_ptbr_{i:02d}.wav'
        sf.write(path, arr, model.sr)
        duration = len(arr) / model.sr
        row = {'model':'Chatterbox-Multilingual-pt-br','text':text,'path':str(path),'duration_s':duration,'generation_s':elapsed,'rtf':elapsed/max(duration,1e-9)}
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False))
    (root / 'chatterbox_ptbr_metrics.json').write_text(json.dumps({'model_repo':'ResembleAI/Chatterbox-Multilingual-pt-br','model_revision':'b3952f18bc2eaa72b9bd7c17d2c4653bcad4770d','base_repo':'ResembleAI/chatterbox','base_revision':'5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18','space_revision':'9e515821e826e207cd617a0fdd0223899ed108ea','load_seconds':load_s,'results':rows},ensure_ascii=False,indent=2),encoding='utf-8')
'''), encoding='utf-8')

texts_json = ROOT / 'texts.json'
texts_json.write_text(json.dumps(TEXTS, ensure_ascii=False), encoding='utf-8')
print('\nExecutando Chatterbox PT-BR (referência permanece no Colab)...')
subprocess.run([str(chat_py), str(chat_runner), str(ROOT), str(space_dir), str(REF_WAV), str(texts_json)], check=True, env=CHILD_ENV)

# ---------- Qwen3-TTS: fine-tunable Base 0.6B, português genérico ----------
qwen_py = make_env('qwen3_tts', [
    '--no-deps', 'qwen-tts==0.1.1',
])
qwen_site = next((p for p in (qwen_py.parent.parent / 'lib').glob('python*/site-packages')), None)
if qwen_site is None:
    raise RuntimeError('Não encontrei site-packages no ambiente isolado Qwen.')
subprocess.run([sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check', '--no-warn-script-location',
                '--upgrade', '--target', str(qwen_site), 'transformers==4.57.3', 'accelerate==1.12.0', 'librosa', 'soundfile', 'sox', 'onnxruntime', 'einops', 'huggingface_hub==0.36.2'], check=True, env=CHILD_ENV)

qwen_runner = ROOT / 'run_qwen_pt.py'
qwen_runner.write_text(textwrap.dedent(r'''
    import json, sys, time
    from pathlib import Path
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download
    from qwen_tts import Qwen3TTSModel

    root=Path(sys.argv[1]); ref_path=Path(sys.argv[2]); ref_text=sys.argv[3]
    texts=json.loads(Path(sys.argv[4]).read_text(encoding='utf-8'))
    model_dir=snapshot_download(
        repo_id='Qwen/Qwen3-TTS-12Hz-0.6B-Base',
        revision='5d83992436eae1d760afd27aff78a71d676296fc',
    )
    t0=time.perf_counter()
    model=Qwen3TTSModel.from_pretrained(
        model_dir, device_map='cuda:0', dtype=torch.float16,
        attn_implementation='sdpa',
    )
    load_s=time.perf_counter()-t0
    print(f'Qwen3-TTS Base 0.6B carregado em {load_s:.2f}s (FP16/SDPA);')
    rows=[]
    for i,text in enumerate(texts,1):
        torch.manual_seed(1234)
        t0=time.perf_counter()
        wavs,sr=model.generate_voice_clone(
            text=text, language='Portuguese', ref_audio=str(ref_path), ref_text=ref_text,
        )
        elapsed=time.perf_counter()-t0
        arr=wavs[0]
        path=root/f'qwen3_tts_pt_{i:02d}.wav'
        sf.write(path,arr,sr)
        duration=len(arr)/sr
        row={'model':'Qwen3-TTS-12Hz-0.6B-Base','text':text,'path':str(path),'duration_s':duration,'generation_s':elapsed,'rtf':elapsed/max(duration,1e-9)}
        rows.append(row)
        print(json.dumps(row,ensure_ascii=False))
    (root/'qwen3_tts_metrics.json').write_text(json.dumps({'model_repo':'Qwen/Qwen3-TTS-12Hz-0.6B-Base','model_revision':'5d83992436eae1d760afd27aff78a71d676296fc','package':'qwen-tts==0.1.1','load_seconds':load_s,'results':rows},ensure_ascii=False,indent=2),encoding='utf-8')
'''), encoding='utf-8')

print('\nExecutando Qwen3-TTS Base 0.6B (ref_text deve corresponder literalmente ao WAV)...')
subprocess.run([str(qwen_py), str(qwen_runner), str(ROOT), str(REF_WAV), REF_TEXT, str(texts_json)], check=True, env=CHILD_ENV)

# Toca todas as amostras no notebook, intercaladas por frase para comparação cega.
from IPython.display import Audio, display, Markdown
print('\nConcluído. Arquivos e métricas em:', ROOT)
for i, text in enumerate(TEXTS, 1):
    display(Markdown(f'### Frase {i}: {text}'))
    for label, filename in [
        ('Chatterbox PT-BR', f'chatterbox_ptbr_{i:02d}.wav'),
        ('Qwen3-TTS Base', f'qwen3_tts_pt_{i:02d}.wav'),
    ]:
        print(label)
        display(Audio(filename=str(ROOT / filename)))

print('Latência de síntese (não é streaming/TTFA) e RTF:')
for fn in ['chatterbox_ptbr_metrics.json','qwen3_tts_metrics.json']:
    data=json.loads((ROOT/fn).read_text(encoding='utf-8'))
    print(fn, '| carga=%.2fs' % data['load_seconds'])
    for r in data['results']:
        print(r['model'], '| geração=%.2fs | áudio=%.2fs | RTF=%.3f |' % (r['generation_s'],r['duration_s'],r['rtf']), r['text'])
