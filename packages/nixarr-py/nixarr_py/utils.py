"""
Utilities for working with Nixarr services in Python.
"""

from typing import Any


def expand_secret(value: Any) -> Any:
    if not isinstance(value, dict) or "secret" not in value:
        return value
    with open(value["secret"], "r", encoding="utf-8") as file_handle:
        return file_handle.read().strip()


def apply_config(
    user_src: dict[str, Any],
    arr_dst: dict[str, Any],
    unchecked_user_properties: list[str] = [],
) -> None:
    unexpected_items: list[str] = []

    arr_field_names = [field["name"] for field in arr_dst["fields"]]

    for property_name, property_value in user_src.items():
        if property_name in unchecked_user_properties:
            continue
        if property_name not in arr_dst:
            unexpected_items.append(f'."{property_name}"')
            continue
        if property_name != "fields":
            continue
        user_fields = property_value
        for field_name in user_fields:
            if field_name not in arr_field_names:
                unexpected_items.append(f'.fields."{field_name}"')

    if unexpected_items:
        raise ValueError(
            (
                "The following properties/fields are present in the user config but "
                "not in the *arr config: "
                f"{', '.join(unexpected_items)}."
            )
        )

    for property_name, property_value in user_src.items():
        if property_name != "fields":
            arr_dst[property_name] = expand_secret(property_value)
            continue

        user_fields = property_value
        for arr_field in arr_dst["fields"]:
            field_name = arr_field["name"]
            if field_name in user_fields:
                arr_field["value"] = expand_secret(user_fields[field_name])