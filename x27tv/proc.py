# Async command runner shared by the backends: runs a program via QProcess and hands
# (exit code, stdout, stderr) to a callback without blocking the UI.

import shutil

from PySide6.QtCore import QProcess


def run(parent, program, args, callback=None):
    if not shutil.which(program):
        if callback:
            callback(-1, "", f"{program} not found")
        return None
    proc = QProcess(parent)

    def done(code, status):
        try:
            out = bytes(proc.readAllStandardOutput()).decode(errors="replace")
            err = bytes(proc.readAllStandardError()).decode(errors="replace")
            proc.deleteLater()
        except RuntimeError:
            return
        if callback:
            callback(code if status == QProcess.NormalExit else -1, out, err)

    proc.finished.connect(done)
    proc.start(program, args)
    return proc


def sh(parent, script, callback=None):
    return run(parent, "sh", ["-c", script], callback)
