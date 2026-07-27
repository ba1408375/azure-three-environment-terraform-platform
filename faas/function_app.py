import json
from datetime import datetime, timezone

import azure.functions as func


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.function_name(name="DevCloudFaaS")
@app.route(route="faas", methods=["GET", "POST"])
def faas(req: func.HttpRequest, context: func.Context) -> func.HttpResponse:
    """Small HTTP FaaS endpoint used to verify the Azure deployment."""
    response = {
        "service": "devcloud-faas",
        "cloud": "azure",
        "status": "ready",
        "invocation_id": context.invocation_id,
        "method": req.method,
        "url": req.url,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    return func.HttpResponse(
        body=json.dumps(response),
        status_code=200,
        mimetype="application/json",
    )
