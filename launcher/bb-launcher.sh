#!/usr/bin/env bash
# Starts the Bloodborne launcher (GTK4). With Python, PyGObject, GTK 4 and libadwaita installed
# it runs directly; otherwise through nix-shell (launcher/shell.nix).
here=$(cd -- "$(dirname -- "$0")" && pwd)
# macOS: Homebrew's Python has the PyGObject, GTK 4 and libadwaita from
# brew install pygobject3 gtk4 libadwaita
if [[ $(uname -s) == Darwin ]]; then
    for python in /opt/homebrew/bin/python3 /opt/homebrew/bin/python3.1[0-9] /usr/local/bin/python3; do
        if [[ -x $python ]] && "$python" -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")' 2>/dev/null; then
            exec "$python" "$here/bbport_launcher.py" "$@"
        fi
    done
    echo 'Need GTK 4 for the launcher: brew install pygobject3 gtk4 libadwaita' >&2; exit 1
fi
if python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")' 2>/dev/null; then
    exec python3 "$here/bbport_launcher.py" "$@"
fi
exec nix-shell "$here/shell.nix" --run "python3 '$here/bbport_launcher.py'"
