"""Rem - Server-Side Data Layer.

Messages are stored as `Message` nodes on the graph and persist across
restarts. The walkers below are the API the client calls with `root spawn`.

They are `:pub`, so they need no login: `root` is the shared global graph and
every visitor reads and writes the same guestbook. Switch a walker to `:priv`
to require authentication and give each user their own isolated `root`.

The walkers report `Message` nodes directly. Typing `reports` as
`list[Message]` makes `(spawn W).reports` a typed `list[Message]` on the client,
so the UI gets `.author` / `.text` dot access instead of untyped dict keys.
"""

# Person B walkers, re-exported through the service module.
# `jac start` auto-detects microservice mode from this .sv.jac file and the
# gateway only derives routes from the SERVICE -- walkers living in plain root
# modules never register, and POST /walker/<name> 404s even when main.jac
# imports them. Importing them here puts them on the served surface at
# /endpoints/walker/<name>. APPEND-ONLY: add lines, never reorder.
import from baseline { Baseline }
import from ingest { IngestDevice, IngestTranscript }
import from omission { OmissionPanel }

node Message {
    has author: str,
        text: str;
}

walker:pub PostMessage {
    """Append a new message and report the created node."""
    has author: str,
        text: str,
        reports: list[Message] = [];

    can post with Root entry {
        report here ++> Message(author=self.author, text=self.text);
    }
}

walker:pub ListMessages {
    """Report every message in the guestbook, one report per node."""
    has reports: list[Message] = [];

    can collect with Root entry {
        visit [-->];
    }

    can gather with Message entry {
        report here;
    }
}
