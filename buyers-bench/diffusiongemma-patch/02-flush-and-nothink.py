# LOCAL bench patch for llama.cpp PR #24423 (examples/diffusion/diffusion-cli.cpp) -- not upstream. Run, then rebuild llama-diffusion-cli.
from pathlib import Path
p = Path.home() / "diffusiongemma/llama.cpp/examples/diffusion/diffusion-cli.cpp"; s = p.read_text()
old = """            if (getenv("DG_ESCAPED")) { printf("\\n<<<DG_END>>>\\n"); fflush(stdout); }"""
assert s.count(old) == 1
# the reply goes out through the async logger: flush it first, or the marker overtakes the reply
s = s.replace(old, """            if (getenv("DG_ESCAPED")) { common_log_flush(common_log_main()); fflush(stdout); printf("\\n<<<DG_END>>>\\n"); fflush(stdout); }""")
old = """        inputs.add_generation_prompt = true;"""
assert s.count(old) == 1
s = s.replace(old, old + """
        if (getenv("DG_NOTHINK")) inputs.enable_thinking = false;   // LOCAL BENCH PATCH: match humaneval.py (thinking off)""")
p.write_text(s); print("patched")
