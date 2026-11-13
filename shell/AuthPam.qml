import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

// shortcut: never run here because tests stay on the fake authenticator, verify on the OS
Item {
    property string pending: ""
    property string account: ""
    property bool waiting: false
    property bool dirKnown: false

    function submit(user, password) {
        pending = password;
        account = user;
        if (!dirKnown)
            waiting = true;
        else
            begin();
    }
    function begin() {
        waiting = false;
        pam.user = account;
        if (!pam.start()) {
            pending = "";
            Auth.finish(false);
        }
    }

    // distros with stateless /etc (Nura, recent Alpine) keep the login stack in /usr/lib/pam.d only
    Process {
        running: true
        command: ["sh", "-c", "test -e /etc/pam.d/login || test ! -e /usr/lib/pam.d/login && echo /etc/pam.d || echo /usr/lib/pam.d"]
        stdout: StdioCollector {
            onStreamFinished: {
                pam.configDirectory = text.trim() || "/etc/pam.d";
                dirKnown = true;
                if (waiting)
                    begin();
            }
        }
    }

    PamContext {
        id: pam
        onPamMessage: if (responseRequired) { respond(pending); pending = ""; }
        onCompleted: result => { pending = ""; Auth.finish(result === PamResult.Success); }
    }
}
