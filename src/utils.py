import os
import json
from azure.ai.projects.operations import AgentsOperations
from azure.ai.projects.models import CodeInterpreterTool, FileSearchTool, BingGroundingTool

def create_or_update_agent(
        agents_client: AgentsOperations,
        agent_name: str
    ) -> str:
    # Create agent if it doesn't exist
    agents = agents_client.list_agents(limit=100)

    options = {
        "name": agent_name,
        "model": os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME"),
        "instructions": os.getenv("LLM_INSTRUCTIONS"),
        "tools": [
            *CodeInterpreterTool().definitions,
            *FileSearchTool().definitions,
            # *BingGroundingTool(connection_id=os.getenv("AZURE_BING_CONNECTION_ID")).definitions
        ],
        "headers": {"x-ms-enable-preview": "true"}
    }

    for tool in os.listdir("tools"):
        if tool.endswith(".json"):
            with open(f"tools/{tool}", "r") as f:
                options["tools"].append(json.loads(f.read()))
    if agents.has_more:
        raise Exception("Too many agents")
    for agent in agents.data:
        if agent.name == os.getenv("AZURE_OPENAI_AGENT_NAME"):
            options["assistant_id"] = agent.id
            agent = agents_client.update_agent(**options)
            break
    if "assistant_id" not in options:
        agent = agents_client.create_agent(**options)
        options["assistant_id"] = agent.id
    return options["assistant_id"]