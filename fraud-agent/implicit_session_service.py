from typing import Any, Optional, Dict
from typing_extensions import override

from google.adk.sessions import BaseSessionService
from google.adk.sessions import Session
from google.adk.events import Event


class ImplicitSessionService(BaseSessionService):
  """
  A session service that proxies another BaseSessionService instance.

  It ensures that the `get_session` method always returns an active Session
  object, automatically listing existing sessions and creating a new one
  if none are found for the given user.
  """

  def __init__(self, proxied_service: BaseSessionService):
    """
    Initializes the service with another session service to proxy to.

    Args:
        proxied_service: An instance of a class that implements
                         BaseSessionService.
    """
    if not isinstance(proxied_service, BaseSessionService):
      raise TypeError("proxied_service must be an instance of BaseSessionService")
    self._proxied_service = proxied_service

  @override
  async def get_session(
      self,
      *,
      app_name: str,
      user_id: str,
      session_id: str,
      # The configuration structure is often opaque, so we use Any
      config: Optional[Any] = None,
  ) -> Session:
    """
    Gets a session for a user, creating one if it does not exist.
    Assumes a maximum of one relevant session per user.

    This method is guaranteed to return a Session object.
    """
    # print("Get session " + user_id + " ") # Debugging line commented out

    # Check if the user already has a session created via the proxy service.
    sessions_list = await self._proxied_service.list_sessions(
        app_name=app_name,
        user_id=user_id,
    )

    if sessions_list.sessions:
      # If sessions exist, get the first one. We must call get_session
      # again because list_sessions often returns session stubs (without events).
      existing_session_id = sessions_list.sessions[0].id
      session = await self._proxied_service.get_session(
          app_name=app_name,
          user_id=user_id,
          session_id=existing_session_id,
          config=config
      )
    else:
      # print("Creating a session") # Debugging line commented out
      # Create a new session with an empty state.
      session = await self._proxied_service.create_session(
          app_name=app_name,
          user_id=user_id,
          state=None,
      )

    # print("Got session " + user_id) # Debugging line commented out
    return session

  @override
  async def create_session(
      self,
      *,
      app_name: str,
      user_id: str,
      state: Optional[dict[str, Any]] = None,
      session_id: Optional[str] = None,
  ) -> Session:
    """Proxies the create_session call to the underlying service."""
    return await self._proxied_service.create_session(
        app_name=app_name,
        user_id=user_id,
        state=state,
        session_id=session_id,
    )

  @override
  async def list_sessions(
      self, *, app_name: str, user_id: str
  ) -> Any:  # Returns a ListSessionsResponse object (using Any for simplicity)
    """Proxies the list_sessions call to the underlying service."""
    return await self._proxied_service.list_sessions(
        app_name=app_name, user_id=user_id
    )

  @override
  async def delete_session(
      self, *, app_name: str, user_id: str, session_id: str
  ) -> None:
    """Proxies the delete_session call to the underlying service."""
    await self._proxied_service.delete_session(
        app_name=app_name, user_id=user_id, session_id=session_id
    )

  @override
  async def append_event(self, session: Session, event: Event) -> Event:
    """Proxies the append_event call to the underlying service."""
    return await self._proxied_service.append_event(session, event)