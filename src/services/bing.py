import json
import requests

class BingClient():
    def __init__(self, api_key: str, endpoint="https://api.bing.microsoft.com/v7.0/search"):
        self.endpoint = endpoint
        self.headers = {"Ocp-Apim-Subscription-Key": api_key}
        pass

    def query(self, query: str, type: str):
        params = {"q": query, "textDecorations": True, "textFormat": "HTML"}
        response = requests.get(self.endpoint, headers=self.headers, params=params)
        response.raise_for_status()
        search_results = response.json()
        return json.dumps(search_results)