def frame_str(frame):
  """Formats an api_pb2.Frame as a human-readable string."""
  return "[(%s, %s) %s]" % (
      frame.origin.x,
      frame.origin.y,
      size_str(frame.size))

def size_str(size):
  """Formats an api_pb2.Size as a human-readable string."""
  return "(%s x %s)" % (
      size.width,
      size.height)

