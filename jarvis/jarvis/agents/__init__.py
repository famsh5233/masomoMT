LANGUAGES = {
    # Beachhead first (existing Masomo audience), then the largest English-learner
    # populations the big apps under-serve in their own language.
    "sw": "Swahili", "ha": "Hausa", "yo": "Yoruba", "am": "Amharic", "so": "Somali",
    "fr": "French", "pt": "Portuguese", "ar": "Arabic", "hi": "Hindi", "bn": "Bengali",
    "ur": "Urdu", "id": "Indonesian", "vi": "Vietnamese", "tr": "Turkish", "es": "Spanish",
}

LEVELS = ["A1", "A2", "B1", "B2", "C1"]


def lang_name(code: str) -> str:
    return LANGUAGES.get(code, "Swahili")
