import Quickshell.Services.Greetd
import QtQuick

// shortcut: never run here because no greetd config may be touched yet, verify on the OS
Item {
    property string pending: ""

    function submit(account, password) {
        pending = password;
        Greetd.createSession(account);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            Greetd.respond(responseRequired ? pending : "");
            pending = "";
        }
        function onAuthFailure(message) { pending = ""; Greetd.cancelSession(); Auth.finish(false); }
        function onError(error) { pending = ""; Auth.finish(false); }
        function onReadyToLaunch() { Greetd.launch(["sh", "-c", Auth.sessionCommand]); }
        function onLaunched() { Qt.quit(); }
    }
}
