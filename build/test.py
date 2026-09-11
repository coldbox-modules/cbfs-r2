#!/usr/bin/env python3
"""Run the package's own TestBox harness in a disposable, loopback-only server."""
import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from urllib.request import urlopen
from urllib.error import HTTPError
import uuid

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {".git", ".engine", ".artifacts", ".tmp", "modules", "coldbox", "testbox", "__pycache__", "results"}


def excluded(directory, names):
    return [name for name in names if name in IGNORED or name.startswith(".env") and name != ".env.example"]


def hashes():
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in ROOT.rglob("*") if path.is_file() and not any(part in IGNORED for part in path.relative_to(ROOT).parts)
            and not path.name.startswith(".env")}



def stage_sdk(manifest, workspace, sdk_source=None):
    """Use a local SDK only when explicitly requested, never by sibling discovery."""
    if manifest["slug"] != "cbfs-r2":
        if sdk_source is not None:
            raise ValueError("--sdk-source applies only to cbfs-r2")
        return
    if sdk_source is not None:
        source = sdk_source.resolve()
        if not source.is_dir():
            raise ValueError("The explicit SDK source directory does not exist")
        descriptor = json.loads((source / "box.json").read_text())
        if descriptor.get("slug") != "r2sdk":
            raise ValueError("The explicit SDK source is not r2sdk")
        shutil.copytree(source, workspace / "r2sdk", ignore=excluded)
        manifest["dependencies"]["r2sdk"] = str(workspace / "r2sdk") + "/"
    elif manifest["dependencies"]["r2sdk"].startswith("."):
        raise ValueError("Supply --sdk-source until r2sdk has a published dependency version")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default="boxlang@1.17.2+56")
    parser.add_argument("--sdk-source", type=Path, help="Local r2sdk source while its first release is unpublished")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="r2-module-results-"))
    if output.is_relative_to(ROOT):
        parser.error("Evidence must be outside the package source")
    if args.output:
        output.mkdir(parents=True, mode=0o700, exist_ok=False)
    before = hashes()
    started = time.monotonic()
    report = {"passed": False, "engine": args.engine, "sourceSha256": before, "cleanup": {}}
    sidecar = None
    active = None
    configuration = None
    name = "r2-module-" + uuid.uuid4().hex
    env = {**os.environ, "BOX_CONFIG_modulesExclude": '["commandbox-hostupdater"]'}

    def interrupt(signum, frame):
        raise KeyboardInterrupt()

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)

    def command(label, arguments, cwd, timeout=600, required=True):
        nonlocal active
        print("RUN " + label, flush=True)
        with (output / (label + ".log")).open("w") as log:
            active = subprocess.Popen(arguments, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                code = active.wait(timeout=timeout)
            finally:
                if active.poll() is None:
                    active.terminate()
                    try:
                        active.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        active.kill()
                        active.wait()
                active = None
        if required and code:
            raise RuntimeError(label + " failed; see its log")
        return code

    with tempfile.TemporaryDirectory(prefix="r2-module-work-") as temporary:
        workspace = Path(temporary)
        slug = json.loads((ROOT / "box.json").read_text())["slug"]
        package = workspace / slug
        shutil.copytree(ROOT, package, ignore=excluded)
        try:
            manifest = json.loads((package / "box.json").read_text())
            stage_sdk(manifest, workspace, args.sdk_source)
            (package / "box.json").write_text(json.dumps(manifest, indent=2) + "\n")
            command("dependencies", ["box", "install", "--production"], package)
            command("harness-dependencies", ["box", "install"], package / "test-harness")
            sidecar = subprocess.Popen(["python3", str(package / "test-harness/tests/resources/r2_contract_server.py")],
                                       stdout=subprocess.PIPE, stderr=(output / "contract.log").open("w"), text=True)
            if not select.select([sidecar.stdout], [], [], 10)[0]:
                raise RuntimeError("Contract server did not start")
            env["R2_CONTRACT_PORT"] = str(int(sidecar.stdout.readline()))
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            configuration = package / "server-test.json"
            server = {"name": name, "openBrowser": False,
                      "app": {"cfengine": args.engine, "serverHomeDirectory": str(workspace / "engine")},
                      "web": {"host": "127.0.0.1", "http": {"port": port}, "webroot": "test-harness", "directoryBrowsing": False},
                      "JVM": {"heapSize": 512},
                      "env": {"R2_CONTRACT_PORT": env["R2_CONTRACT_PORT"]}}
            if args.engine.startswith("boxlang"):
                server["scripts"] = {"onServerInitialInstall": "install bx-esapi@1.10.0+14"}
            configuration.write_text(json.dumps(server, indent=2))
            command("server-start", ["box", "server", "start", "serverConfigFile=" + str(configuration), "saveSettings=false"], package)
            try:
                with urlopen(f"http://127.0.0.1:{port}/tests/runner.cfm", timeout=180) as response:
                    body = response.read()
            except HTTPError as error:
                (output / "http-error.html").write_bytes(error.read())
                raise
            (output / "http-response.txt").write_bytes(body)
            result = json.loads(body)
            (output / "testbox.json").write_text(json.dumps(result, indent=2) + "\n")
            report["runtime"] = {key: result.get(key) for key in ("CFMLEngine", "CFMLEngineVersion") }
            report["tests"] = {key: result.get(key) for key in ("totalPass", "totalFail", "totalError", "totalSkipped", "totalSpecs")}
            if int(result["totalSpecs"]) == 0 or any(int(result[key]) for key in ("totalFail", "totalError", "totalSkipped")):
                raise RuntimeError("TestBox did not pass every discovered test")
            report["passed"] = True
        except (Exception, KeyboardInterrupt) as error:
            report["error"] = str(error)
            report["errorType"] = type(error).__name__
        finally:
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            for log_path in workspace.rglob("*.log"):
                if "engine" in log_path.parts:
                    target = output / "runtime-logs" / log_path.relative_to(workspace)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(log_path, target)
            if configuration:
                command("server-stop", ["box", "server", "stop", "name=" + name], package, timeout=90, required=False)
                with socket.socket() as listener:
                    report["cleanup"]["serverStopped"] = listener.connect_ex(("127.0.0.1", port)) != 0
                if report["cleanup"]["serverStopped"]:
                    command("server-forget", ["box", "server", "forget", "name=" + name, "--force"], package, timeout=60, required=False)
            if sidecar:
                sidecar.terminate()
                try:
                    sidecar.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    sidecar.kill()
                    sidecar.wait()
                report["cleanup"]["contractStopped"] = sidecar.poll() is not None
    report["cleanup"]["workspaceRemoved"] = not workspace.exists()
    report["sourceUnchanged"] = before == hashes()
    report["passed"] = report["passed"] and report["sourceUnchanged"] and all(report["cleanup"].values())
    report["seconds"] = round(time.monotonic() - started, 2)
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(("PASS " if report["passed"] else "FAIL ") + str(output / "summary.json"), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    # CommandBox shares a server registry across invocations on one host.
    # Serialize this runner's lifecycle to avoid racing its initial-install hook.
    with (Path(tempfile.gettempdir()) / "r2-module-test.lock").open("a") as lock:
        print("Waiting for module test lock", flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        raise SystemExit(main())
