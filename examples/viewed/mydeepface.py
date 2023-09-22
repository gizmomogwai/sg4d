#!/opt/homebrew/opt/python@3.11/bin/python3.11
# -*- coding: utf-8 -*-
import re
import sys
from deepface import DeepFace

import cv2

def log(s):
    print("deepface: " + s, file=sys.stderr)

def main():
    identities = sys.argv[1]

    for line in sys.stdin:
        line = line.strip()
        log(line)
        if line == "quit":
            print("Quitting")
            break

        image, cache_path = line.split(",")

        faces = DeepFace.find(
            img_path = image,
            db_path = identities,
            model_name = "Facenet512",
            detector_backend = "retinaface",
            silent = True,
            enforce_detection=False,
        )
        h = "["
        for index, face in enumerate(faces):
            face_file_name = f"{cache_path}/face-{index}.jpg"
            if h != "[":
                h += ","
            h += "{\"confidence\":"
            h += str(face["confidence"])
            h += ", \"region\":" + str(face["region"]).replace("'", "\"")
            h += ", \"file_name\":\"" + face_file_name + "\""
            h += ", \"match\":"
            detected_face = face["normalized_image"] * 255
            cv2.imwrite(face_file_name, detected_face)
            h += face["match_result"].to_json(orient="records")
            h += "}"
        h += "]"
        h.replace("\n", " ")
        print(h)
        sys.stdout.flush()
        log("done with " + image)

if __name__ == '__main__':
    main()
