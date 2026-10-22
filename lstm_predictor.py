from pathlib import Path
from threading import Lock

import torch
from torch import nn


class WeedLSTM(nn.Module):
    def __init__(self):
        super().__init__()
        self.lstm = nn.LSTM(1, 32, batch_first=True)
        self.fc = nn.Linear(32, 1)

    def forward(self, x):
        output, _ = self.lstm(x)
        return self.fc(output[:, -1])


MODEL_PATH = Path(__file__).resolve().parent / "weed_lstm_demo.pt"

checkpoint = torch.load(
    MODEL_PATH,
    map_location="cpu",
    weights_only=True,
)

model = WeedLSTM()
model.load_state_dict(checkpoint["model_state_dict"])
model.eval()

model_lock = Lock()


def predict_demo(history):
    values = torch.tensor(history, dtype=torch.float32)

    if values.shape != (6,):
        raise ValueError("Exactly 6 historical scores are required.")

    if not torch.isfinite(values).all():
        raise ValueError("Scores must be finite numbers.")

    if ((values < 0) | (values > 1)).any():
        raise ValueError("Scores must be between 0 and 1.")

    with model_lock, torch.inference_mode():
        prediction = model(values.reshape(1, 6, 1)).item()

    return {
        "mode": "synthetic_demo",
        "history": values.tolist(),
        "predicted_next_score": round(
            max(0.0, min(1.0, prediction)), 4
        ),
        "note": (
            "Synthetic-data demonstration only. "
            "This score is not a validated field forecast, "
            "weed count, or weeds per square metre."
        ),
    }