# -*- coding: utf-8 -*-
"""
deep_space_thermal_twin.py - Deep-Space Thermal Vacuum Digital Twin Engine
==============================================================================
Project: Phantom Grid Space Systems
Subsystem: Core Controller Vacuum Thermoelectric Physics & Autonomous Survival
Environment: 10^-6 Torr Deep Space Vacuum (Zero-Convection h_conv = 0)
Radiation: Stefan-Boltzmann Law (q_rad = epsilon * sigma * A * (T^4 - T_space^4))
Extreme Bounds: +120°C (Sunlit Heat Soak) to -150°C (Shadow Crater Shock)
==============================================================================
"""

from dataclasses import dataclass
from typing import Dict, Tuple

# Physical & Material Constants
SIGMA_STEFAN_BOLTZMANN = 5.670374419e-8  # W / (m^2 * K^4)
KELVIN_OFFSET = 273.15  # 0°C in Kelvin


@dataclass
class ThermalTwinParams:
    # Thermal capacitance of controller core (J/K)
    c_th: float = 65.0
    # Conductive conductance to chassis mount (W/K) via thermal standoffs
    g_cond: float = 0.20
    # Radiator surface area (m^2)
    a_rad: float = 0.08
    # Surface thermal emissivity (0.0 to 1.0)
    emissivity: float = 0.88
    # Solar absorptivity
    absorptivity: float = 0.20
    # Projected solar area (m^2)
    a_solar: float = 0.025
    # Solar flux at 1 AU (W/m^2)
    solar_flux: float = 1361.0
    # Convective heat transfer coefficient (W/(m^2*K)), 0.0 in vacuum
    h_conv: float = 0.0
    # Convective area (m^2)
    a_conv: float = 0.08
    # Junction-to-case thermal resistance (K/W)
    r_th_jc: float = 0.38
    # Inverter phase winding resistance (Ohm)
    r_phase: float = 0.025
    # Baseline controller idle power (W)
    p_idle: float = 2.5
    # Maximum nominal drive compute/inverter power (W)
    p_drive_nominal: float = 60.0


class DeepSpaceThermalTwin:
    """Second-Order Non-Linear Thermoelectric Digital Twin for Spacecraft Controllers."""

    def __init__(self, params: ThermalTwinParams | None = None) -> None:
        self.p = params or ThermalTwinParams()
        # Initialize at standard room temperature (25°C)
        self.t_core_k: float = 25.0 + KELVIN_OFFSET
        # Environmental state
        self.in_vacuum: bool = True
        self.sunlit: bool = True
        self.t_space_k: float = 120.0 + KELVIN_OFFSET
        self.t_chassis_k: float = 25.0 + KELVIN_OFFSET

        # Autonomous control actuators
        self.self_heating_active: bool = False
        self.id_current_amps: float = 0.0
        self.derating_ratio: float = 1.0

    def set_environment(
        self,
        in_vacuum: bool,
        sunlit: bool,
        t_env_c: float,
        t_chassis_c: float | None = None,
    ) -> None:
        """Dynamically configure external thermal-vacuum boundary conditions."""
        self.in_vacuum = in_vacuum
        self.sunlit = sunlit
        self.t_space_k = t_env_c + KELVIN_OFFSET
        self.t_chassis_k = (
            (t_chassis_c + KELVIN_OFFSET)
            if t_chassis_c is not None
            else self.t_space_k
        )
        self.p.h_conv = 0.0 if in_vacuum else 15.0

    def compute_heat_fluxes(
        self, t_k: float, p_internal: float
    ) -> Tuple[float, float, float, float, float]:
        """Compute all instantaneous heat dissipation and absorption terms."""
        # 1. Stefan-Boltzmann thermal radiation (Non-linear T^4)
        if self.in_vacuum:
            q_rad = (
                self.p.emissivity
                * SIGMA_STEFAN_BOLTZMANN
                * self.p.a_rad
                * (t_k**4 - self.t_space_k**4)
            )
        else:
            q_rad = 0.0

        # 2. Convection (strictly 0.0 in 10^-6 Torr vacuum)
        q_conv = self.p.h_conv * self.p.a_conv * (t_k - self.t_space_k)

        # 3. Solid conduction to vehicle chassis structure
        q_cond = self.p.g_cond * (t_k - self.t_chassis_k)

        # 4. Direct solar irradiation flux
        q_solar = (
            (self.p.absorptivity * self.p.solar_flux * self.p.a_solar)
            if (self.sunlit and self.in_vacuum)
            else 0.0
        )

        # 5. Autonomous self-heating via zero-torque d-axis circulating current
        # P_heat = 3 * I_d^2 * R_phase
        q_self_heat = (
            (3.0 * (self.id_current_amps**2) * self.p.r_phase)
            if self.self_heating_active
            else 0.0
        )

        return q_rad, q_conv, q_cond, q_solar, q_self_heat

    def step(
        self, duration_s: float, dt_s: float = 0.05, is_driving: bool = True
    ) -> Dict[str, float | bool]:
        """Execute closed-loop digital twin physics integration over duration."""
        steps = int(duration_s / dt_s)
        dt = duration_s / steps if steps > 0 else duration_s

        p_drive_base = self.p.p_drive_nominal if is_driving else 0.0

        for _ in range(max(1, steps)):
            t_core_c = self.t_core_k - KELVIN_OFFSET

            # --- Autonomous Survival Control Loop ---
            # Action A: Shadow Cryogenic Zone Autonomous Self-Heating
            # Prevent electrolyte freezing & solder joint shear (< -20°C trigger)
            if t_core_c < -20.0:
                self.self_heating_active = True
                deficit = abs(-20.0 - t_core_c)
                self.id_current_amps = min(22.0, 16.0 + deficit * 0.45)
            elif t_core_c > -5.0:
                self.self_heating_active = False
                self.id_current_amps = 0.0

            # Action B: Sunlit Zone Non-Disruptive Continuous Derating
            # Clamp junction temperature Tj safely below 145.0°C quench limit
            t_j_est_c = (
                t_core_c
                + (self.p.p_idle + p_drive_base * self.derating_ratio)
                * self.p.r_th_jc
            )
            if t_j_est_c > 110.0:
                over_temp = t_j_est_c - 110.0
                self.derating_ratio = max(
                    0.18, round(1.0 - (over_temp / 28.0) * 0.78, 3)
                )
            else:
                self.derating_ratio = 1.0

            # Effective internal electronic power
            p_internal = self.p.p_idle + p_drive_base * self.derating_ratio

            # RK4 Integration for non-linear T^4 differential equation
            def derivative(temp_k: float) -> float:
                q_rad, q_conv, q_cond, q_solar, q_self_heat = (
                    self.compute_heat_fluxes(temp_k, p_internal)
                )
                net_p = (
                    p_internal
                    + q_solar
                    + q_self_heat
                    - q_rad
                    - q_conv
                    - q_cond
                )
                return net_p / self.p.c_th

            k1 = derivative(self.t_core_k)
            k2 = derivative(self.t_core_k + 0.5 * dt * k1)
            k3 = derivative(self.t_core_k + 0.5 * dt * k2)
            k4 = derivative(self.t_core_k + dt * k3)

            self.t_core_k += (dt / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)

        # Final diagnostics
        final_core_c = self.t_core_k - KELVIN_OFFSET
        p_internal = self.p.p_idle + p_drive_base * self.derating_ratio
        final_tj_c = final_core_c + p_internal * self.p.r_th_jc
        q_rad, q_conv, q_cond, q_solar, q_self_heat = self.compute_heat_fluxes(
            self.t_core_k, p_internal
        )

        return {
            "t_core_c": round(final_core_c, 2),
            "t_junction_c": round(final_tj_c, 2),
            "in_vacuum": self.in_vacuum,
            "sunlit": self.sunlit,
            "h_conv": self.p.h_conv,
            "q_radiation_w": round(q_rad, 2),
            "q_conduction_w": round(q_cond, 2),
            "q_solar_w": round(q_solar, 2),
            "self_heating_active": self.self_heating_active,
            "id_current_amps": round(self.id_current_amps, 2),
            "q_self_heat_w": round(q_self_heat, 2),
            "derating_ratio": round(self.derating_ratio, 3),
            "p_internal_w": round(p_internal, 2),
        }
