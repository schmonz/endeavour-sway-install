#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_gl_capable_gpu: thinkpad-t60 sets HAS_GL_CAPABLE_GPU=false" {
    need_specimen "thinkpad-t60/lspci-n.txt"
    probe_has_gl_capable_gpu "$(specimen thinkpad-t60/lspci-n.txt)"
    [[ "$HAS_GL_CAPABLE_GPU" == "false" ]]
}

@test "probe_has_gl_capable_gpu: thinkpad-x270 leaves HAS_GL_CAPABLE_GPU=true" {
    need_specimen "thinkpad-x270/lspci-n.txt"
    probe_has_gl_capable_gpu "$(specimen thinkpad-x270/lspci-n.txt)"
    [[ "$HAS_GL_CAPABLE_GPU" == "true" ]]
}

@test "probe_has_gl_capable_gpu: 1002:5b60 sets HAS_GL_CAPABLE_GPU=false" {
    probe_has_gl_capable_gpu "01:00.0 0300: 1002:5b60"
    [[ "$HAS_GL_CAPABLE_GPU" == "false" ]]
}

@test "probe_has_gl_capable_gpu: 1002:5b62 sets HAS_GL_CAPABLE_GPU=false" {
    probe_has_gl_capable_gpu "01:00.0 0300: 1002:5b62"
    [[ "$HAS_GL_CAPABLE_GPU" == "false" ]]
}

@test "probe_has_gl_capable_gpu: other ATI ID leaves HAS_GL_CAPABLE_GPU=true" {
    probe_has_gl_capable_gpu "01:00.0 0300: 1002:1234"
    [[ "$HAS_GL_CAPABLE_GPU" == "true" ]]
}
