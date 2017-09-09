from .hierarchy import Hierarchy
from .notifications import NewSessionSubscription, TerminateSessionSubscription, KeystrokeSubscription, LayoutChangeSubscription, wait
from .session import Session
from .tab import Tab
from .window import Window
import _sharedstate as sharedstate

def run(function):
  function()
  sharedstate.get_socket().finish()

