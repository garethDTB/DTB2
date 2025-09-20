import azure.functions as func
import logging
import json
import os
from azure.cosmos import CosmosClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

endpoint = os.getenv("COSMOS_ENDPOINT")
key = os.getenv("COSMOS_KEY")
database_name = os.getenv("COSMOS_DATABASE")
container_name = os.getenv("COSMOS_TICKS_CONTAINER")


client = CosmosClient(endpoint, key)
database = client.get_database_client(database_name)
container = database.get_container_client(container_name)

@app.route(route="walls/{wallId}/ticks", auth_level=func.AuthLevel.ANONYMOUS)
def wallTicksGet(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing wall ticks request.')

    wall_id = req.route_params.get("wallId")
    if not wall_id:
        return func.HttpResponse("Missing wallId", status_code=400)

    query = "SELECT c.Problem, c.Count FROM c WHERE c.Wall = @wallId"
    params = [{"name": "@wallId", "value": wall_id}]
    results = list(container.query_items(
        query=query,
        parameters=params,
        enable_cross_partition_query=True
    ))

    return func.HttpResponse(
        json.dumps(results),
        mimetype="application/json",
        status_code=200
    )
