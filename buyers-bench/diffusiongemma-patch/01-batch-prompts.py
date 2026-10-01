# LOCAL bench patch for llama.cpp PR #24423 (examples/diffusion/diffusion-cli.cpp) -- not upstream. Run, then rebuild llama-diffusion-cli.
from pathlib import Path
p = Path.home() / "diffusiongemma/llama.cpp/examples/diffusion/diffusion-cli.cpp"; s = p.read_text()
old = """            messages.push_back(make_msg("user", user));
            const std::string response = run_turn_reply(apply_template(messages));
            messages.push_back(make_msg("assistant", response));"""
assert s.count(old) == 1
new = r"""            // LOCAL BENCH PATCH (not upstream): DG_ESCAPED=1 -> each input line is one message with \n and \\
            // escapes, so a multi-line prompt fits on one line; an end marker lets a driver split the replies.
            if (getenv("DG_ESCAPED")) {
                std::string d; d.reserve(user.size());
                for (size_t i = 0; i < user.size(); i++) {
                    if (user[i] == '\\' && i + 1 < user.size()) {
                        char c = user[++i]; d += (c == 'n') ? '\n' : (c == 't') ? '\t' : c;
                    } else d += user[i];
                }
                user = d;
            }
            messages.push_back(make_msg("user", user));
            const std::string response = run_turn_reply(apply_template(messages));
            messages.push_back(make_msg("assistant", response));
            if (getenv("DG_ESCAPED")) { printf("\n<<<DG_END>>>\n"); fflush(stdout); }"""
p.write_text(s.replace(old, new)); print("patched")
