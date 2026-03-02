import Foundation

let service = "com.crystalidea.macsfancontrol.smcwrite"

func writeKey(_ key: String, _ value: String) -> Bool {
    let conn = xpc_connection_create_mach_service(service, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
    xpc_connection_set_event_handler(conn) { _ in }
    xpc_connection_resume(conn)
    let openMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(openMsg, "command", "open")
    let _ = xpc_connection_send_message_with_reply_sync(conn, openMsg)
    let writeMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(writeMsg, "command", "write")
    xpc_dictionary_set_string(writeMsg, "key", key)
    xpc_dictionary_set_string(writeMsg, "value", value)
    let reply = xpc_connection_send_message_with_reply_sync(conn, writeMsg)
    var ok = false
    if xpc_get_type(reply) == XPC_TYPE_DICTIONARY as xpc_type_t {
        let desc = String(cString: xpc_copy_description(reply))
        ok = desc.contains("OK")
    }
    let closeMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(closeMsg, "command", "close")
    let _ = xpc_connection_send_message_with_reply_sync(conn, closeMsg)
    xpc_connection_cancel(conn)
    return ok
}

if CommandLine.arguments.contains("--restore") {
    let _ = writeKey("F0Md", "00")
    print("Fan 0 restored to auto mode.")
    exit(0)
}

// Daemonize: write values once and exit (called by launchd on interval)
let md = writeKey("F0Md", "01")
let tg = writeKey("F0Tg", "00000000")
if md && tg {
    print("Fan 0: forced off")
} else {
    print("Fan 0: write failed md=\(md) tg=\(tg)")
}
