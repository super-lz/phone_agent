const webAppJsBridgeGuide = '''
Use this guide whenever a Web App needs phone/native capability access.

Runtime contract:
- Do not import or create a custom JSBridge SDK file. Phone Agent Runtime injects window.PhoneAgent before app scripts run.
- Web App code calls window.PhoneAgent. Native access still goes through manifest permissions and Capability Runtime.
- Every capability used by JavaScript must be declared in project_create_web_app.permissions or project_update_web_app.permissions.
- If a permission is missing, do not work around it in JavaScript. Update the Web App permissions.

Required JavaScript pattern:
async function callPhone(capabilityId, input = {}) {
  if (!window.PhoneAgent) {
    return { ok: false, error: 'phone_agent_bridge_unavailable' };
  }
  if (!window.PhoneAgent.isCapabilityAllowed(capabilityId)) {
    return { ok: false, error: 'permission_not_declared', capabilityId };
  }
  return await window.PhoneAgent.callCapability(capabilityId, input);
}

Example:
const result = await callPhone('device.info');
if (!result.ok) {
  console.error(result.error, result.detail || '');
} else {
  console.log(result.output);
}

Helpers:
- window.PhoneAgent.getManifest()
- window.PhoneAgent.getAvailableCapabilities()
- window.PhoneAgent.isCapabilityAllowed(capabilityId)
- window.PhoneAgent.getRuntimeInfo()
- window.PhoneAgent.getDeviceInfo()
- window.PhoneAgent.getCurrentTime()
- window.PhoneAgent.getCurrentLocation()
- window.PhoneAgent.setFlashlight(enabled)
- window.PhoneAgent.readClipboard()
- window.PhoneAgent.writeClipboard(text)
- window.PhoneAgent.pickImage(options)
- window.PhoneAgent.pickImages(options)
- window.PhoneAgent.pickVideo()
- window.PhoneAgent.capturePhoto(options)
- window.PhoneAgent.captureVideo(options)
- window.PhoneAgent.startAudioRecording()
- window.PhoneAgent.stopAudioRecording()
- window.PhoneAgent.cancelAudioRecording()
- window.PhoneAgent.createNote(input)
- window.PhoneAgent.queryNotes(input)
- window.PhoneAgent.readAppFile(path, options)
- window.PhoneAgent.writeAppFile(path, content, options)
- window.PhoneAgent.webSearch(queryOrInput)
- window.PhoneAgent.webFetch(urlOrInput)

Local media outputs:
- camera.capture_photo, media.pick_image, media.pick_images, camera.capture_video, media.pick_video, audio.record_stop, and file.pick_system_file return metadata in result.output.
- If result.output.mediaUrl exists, use it directly for previews: image.src = result.output.mediaUrl, audio.src = result.output.mediaUrl, or video.src = result.output.mediaUrl.
- If result.output.fileUrl or result.output.localUrl exists, use that same-origin URL for user-initiated download or display.
- Do not put result.output.uri file:// URLs directly into img/audio/video elements; prefer mediaUrl/fileUrl/localUrl.

Project creation example:
permissions: ['device.info', 'time.get_current']

Never do:
- Do not call Android/iOS APIs directly from Web JavaScript.
- Do not use navigator.userAgent as a substitute for device.info.
- Do not assume camera, location, clipboard, notification, or files work without declared permissions.
- Do not ignore result.ok; always render a user-visible error or fallback.
''';
