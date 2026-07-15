#!/usr/bin/env python3
"""
Trigger win-build.ps1 inside the Windows VM via QEMU monitor keystrokes.
Usage: python3 scripts/trigger-windows-build.py [container_name]
"""
import socket, time, select, sys

CONTAINER = sys.argv[1] if len(sys.argv) > 1 else "metanoia-windows"
SOCK = "/run/shm/monitor.sock"

class QEMUMon:
    def __init__(self, container):
        self.container = container
    def exec(self, code):
        """Execute Python code inside container via docker exec, return output."""
        import subprocess
        r = subprocess.run(
            ["docker", "exec", "-i", self.container, "python3", "-u"],
            input=code.encode(), capture_output=True, timeout=30
        )
        return r.stdout.decode(), r.stderr.decode()

    def send_keys(self, keys):
        """Send keystrokes to the VM."""
        code = f'''
import socket, time, select
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(10)
sock.connect("{SOCK}")
time.sleep(0.1)
sock.setblocking(False)
while select.select([sock],[],[],0.05)[0]:
    try: sock.recv(4096)
    except: break
sock.setblocking(True)
for k, w in {keys}:
    sock.sendall((f"sendkey {{k}}\\n").encode())
    time.sleep(w)
sock.close()
'''
        self.exec(code)

def main():
    m = QEMUMon(CONTAINER)
    
    print("1/5. Ctrl+C to cancel anything running...")
    m.send_keys([("ctrl-c", 0.5)])
    
    print("2/5. Opening Run dialog (Win+R)...")
    m.send_keys([("meta_l", 0.2), ("r", 1.5)])
    
    print("3/5. Opening PowerShell...")
    # Type: powershell
    codes = [(c, 0.06) for c in "powershell"]
    codes.append(("ret", 3))
    m.send_keys(codes)
    
    print("4/5. Running build script via HTTP...")
    # Short command to download + execute
    s = 'iwr -useb http://172.30.0.1:9999/build.ps1 | iex'
    codes = []
    for ch in s:
        if ch.isupper() or ch in ':_|"!@#$%^&*()<>?+~{}':
            actual = ch.lower()
            shift_map = {':':';','_':'-','|':'\\','"':"'",'!':'1','@':'2','#':'3',
                         '$':'4','%':'5','^':'6','&':'7','*':'8','(':'9',')':'0',
                         '<':',','>':'.','?':'/','+':'=','~':'`','{':'[','}':']',
                         'A':'a','B':'b','C':'c','D':'d','E':'e','F':'f','G':'g',
                         'H':'h','I':'i','J':'j','K':'k','L':'l','M':'m','N':'n',
                         'O':'o','P':'p','Q':'q','R':'r','S':'s','T':'t','U':'u',
                         'V':'v','W':'w','X':'x','Y':'y','Z':'z'}
            actual = shift_map.get(ch, actual)
            codes.append(("shift", 0.04))
            codes.append((actual, 0.03))
            codes.append(("shift", 0.04))
        else:
            km = {'\\':'backslash','-':'minus','.':'dot','/':'slash',' ':'spc',
                  "'":'apostrophe','=':'equal','[':'bracket_left',']':'bracket_right',
                  ',':'comma',';':'semicolon','`':'grave_accent'}
            codes.append((km.get(ch, ch), 0.04))
        codes.append(("", 0.02))  # inter-char delay
    codes.append(("ret", 0))
    m.send_keys(codes)
    
    print("5/5. Build triggered! Check http://localhost:8006")

if __name__ == "__main__":
    main()
