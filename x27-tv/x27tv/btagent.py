# BlueZ pairing agent. Without one, bluetoothd turns down every pairing that needs a yes
# ("No agent available for request type 2"), and nothing else provides one in the kiosk
# session. It accepts requests only while armed, i.e. while the user is searching for or
# pairing a device in Settings, and turns them down otherwise, so nearby devices can't
# pair with the TV on their own. NoInputNoOutput: there's no screen prompt to answer.
# A QDBusVirtualObject that answers raw messages: PySide's QDBusContext.sendErrorReply
# crashes, and rejecting is the point.

from PySide6.QtDBus import QDBusConnection, QDBusInterface, QDBusObjectPath, QDBusServiceWatcher, QDBusVirtualObject

PATH = "/org/x27tv/BluetoothAgent"
CAPABILITY = "NoInputNoOutput"
LEGACY_PIN = "0000"

# What each Agent1 method answers when armed. Display* and Release/Cancel need no answer
# beyond an empty reply and are never rejected. RequestPasskey is always turned down: BlueZ
# doesn't ask a NoInputNoOutput agent for one, and the reply would need a uint32.
ANSWERS = {
    "RequestPinCode": [LEGACY_PIN],
    "RequestConfirmation": [],
    "RequestAuthorization": [],
    "AuthorizeService": [],
}
PASSIVE = {"DisplayPinCode", "DisplayPasskey", "Release", "Cancel"}
REJECTED = {"RequestPasskey"}

INTROSPECTION = """<interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
  <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
  <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
  <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="Cancel"/>
</interface>
"""


class Agent(QDBusVirtualObject):
    def __init__(self, bus=None):
        super().__init__()
        self.armed = False
        self.bus = bus or QDBusConnection.systemBus()
        self.registered = self.bus.isConnected() and self.bus.registerVirtualObject(PATH, self)
        if not self.registered:
            return
        self._watcher = QDBusServiceWatcher("org.bluez", self.bus, QDBusServiceWatcher.WatchForRegistration, self)
        self._watcher.serviceRegistered.connect(self.register)
        self.register()

    def register(self):
        manager = QDBusInterface("org.bluez", "/org/bluez", "org.bluez.AgentManager1", self.bus)
        if manager.isValid():
            manager.call("RegisterAgent", QDBusObjectPath(PATH), CAPABILITY)
            manager.call("RequestDefaultAgent", QDBusObjectPath(PATH))

    def introspect(self, path):
        return INTROSPECTION

    def handleMessage(self, message, connection):
        if message.interface() != "org.bluez.Agent1":
            return False
        member = message.member()
        if member in PASSIVE:
            reply = message.createReply()
        elif member in ANSWERS and self.armed:
            reply = message.createReply()
            reply.setArguments(ANSWERS[member])
        elif member in ANSWERS or member in REJECTED:
            reply = message.createErrorReply("org.bluez.Error.Rejected", "Not pairing right now")
        else:
            return False
        connection.send(reply)
        return True
