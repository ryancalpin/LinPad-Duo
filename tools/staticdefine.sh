#!/bin/bash -e
compile_commands=$1
input=$2
output=$3
dep=$4
# asbestos.c's compile command, minus its own input and outputs. shlex keeps quoted
# arguments (a checkout path with spaces) in one piece; NUL-separated so bash can too.
flags=()
while IFS= read -r -d '' arg; do
    flags+=("$arg")
done < <(python3 - "$compile_commands" "$output" "$dep" <<'END'
import json, shlex, sys
compile_commands, output, dep = sys.argv[1:]
with open(compile_commands) as f:
    commands = json.load(f)
for command in commands:
    if command['file'].endswith('asbestos/asbestos.c'):
        break
args = command['arguments'] if 'arguments' in command else shlex.split(command['command'])
args = args[:-9] + ['-MD', '-MQ', output, '-MF', dep]
sys.stdout.write(''.join(a + '\0' for a in args))
END
)
"${flags[@]}" "$input" -include "$(dirname "$0")/staticdefine.h" -S -o - | \
sed -ne 's:^[[:space:]]*\.ascii[[:space:]]*"\(.*\)".*:\1:;
         /^->/{s:->#\(.*\):/* \1 */:;
         s:^->\([^ ]*\) [\$$#]*\([^ ]*\) \(.*\):#define \1 \2 /* \3 */:;
         s:->::; p;}' > "$output"
# sed magic was copied from the linux kernel build system
