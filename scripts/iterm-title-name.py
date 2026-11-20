"""Pin an iTerm2 session's title to Session Name and stop apps from retitling it (needs the iterm2 venv)."""
import sys

import iterm2


async def main(connection: iterm2.Connection) -> None:
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(sys.argv[1])
    if session is None:
        return
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_title_components([iterm2.profile.TitleComponents.SESSION_NAME])
    # Claude Code retitles the tab (OSC) on /clear; ignore app-set titles so the folder name sticks.
    profile.set_allow_title_setting(False)
    await session.async_set_profile_properties(profile)
    after = await session.async_get_profile()
    print("title=" + ",".join(c.name for c in after.title_components) + f" allow_title_setting={after.allow_title_setting}")


iterm2.run_until_complete(main, retry=False)
