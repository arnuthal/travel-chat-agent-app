import json
import requests

class GraphClient():
    def __init__(self, endpoint="https://graph.microsoft.com/v1.0"):
        self.endpoint = endpoint
        pass

    def schedule_event(self, token: str, subject: str, start: str, end: str):
        body = {
            "subject": subject,
            "start": {
                "dateTime": start,
                "timeZone": "UTC"
            },
            "end": {
                "dateTime": end,
                "timeZone": "UTC"
            }
        }
        response = requests.post(f"{self.endpoint}/me/events", headers={"Authorization": f"Bearer {token}"}, json=body)
        response.raise_for_status()
        search_results = response.json()
        return json.dumps(search_results)