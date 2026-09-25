# -*- coding: utf-8 -*-
from setuptools import setup, find_packages

setup(
    name="phantom-grid-core",
    version="1.0.0",
    author="Jack Hu (jackhu24-ship-it) & PHANTOM GRID Fleet",
    author_email="jackhu24@gmail.com",
    description="PHANTOM GRID Core SDK: Autonomous Dual-Signature Governance, Tri-Tier Memory Engine, Safety Watchdog, and Anti-Entropy Runtime",
    long_description="Independent standard library providing zero-trust multi-sig gate, persistent knowledge solidification, millisecond-level fail-safe watchdog, and semantic anti-entropy egress filtering for edge and automotive systems.",
    long_description_content_type="text/markdown",
    packages=find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
    ],
    python_requires=">=3.9",
)
