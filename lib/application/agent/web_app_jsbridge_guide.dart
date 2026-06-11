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
- window.PhoneAgent.serverFetch(path, options)
- window.PhoneAgent.serverJson(path, options)
- window.PhoneAgent.webSearch(queryOrInput)
- window.PhoneAgent.webFetch(urlOrInput)

Local full-stack server:
- If a Web App needs backend routes, database access, or local file access from normal fetch calls, declare project_create_web_app.server.routes or project_update_web_app.server.routes.
- Server routes are local-only and run inside Phone Agent Runtime. Do not create Node, Express, Next.js API routes, Docker files, or Cloudflare deploy configs for the first local-only version.
- Each route maps method + /api path to one capability id. The capability must also appear in permissions.
- For real backend logic, write a JSON server action file inside the Web App project, then set route.handlerPath, for example server/create-note.json.
- A server action handler uses steps to call capabilities in order. Use templates such as "\$request.title" and "\$steps.create.output.id" inside step input or response.
- Frontend code should call await window.PhoneAgent.serverJson('/api/notes', { method: 'POST', body: { title, content } }) for JSON APIs.
- GET routes receive query parameters as input. POST/PUT/PATCH/DELETE routes receive JSON body fields as input.

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
