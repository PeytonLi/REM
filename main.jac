"""Rem - Entry Point.

Combines server-side endpoints with the client-side UI.
"""

import from endpoints { Message, PostMessage, ListMessages }

# Person B walkers. A REST-only walker self-registers only if an entry module
# references it -- "404 on RPC = nothing references it" (jac-fullstack-patterns).
# Without these lines /walker/Baseline and friends simply do not exist.
# APPEND-ONLY by team agreement (WORKPLAN section 2): add lines, never reorder.
import from baseline { Baseline }
import from ingest { IngestDevice, IngestTranscript }
import from omission { OmissionPanel }
import from realtime { DeepgramToken, IngestUtterance }

# Client-side UI
cl {
    import from .client.App { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
