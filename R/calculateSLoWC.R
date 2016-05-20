#' Calculate the "severity loss of well-clear" (SLoWC) metric, described in RTCA
#' SC-228 Closed-Loop Metrics White Paper.
#' 
#' @param trajectory1 A \code{flighttrajectory} object corresponding to the
#'   first aircraft.
#' @param trajectory2 A \code{flighttrajectory} object corresponding to the
#'   second aircraft.
#' @return The numeric vector giving the SLoWC metric. Values lie in the range 
#'   [0, 100]. A SLoWC of 0 indicates well-clear, while a value of 100 
#'   corresponds to "full penetration" (i.e., a collision).
#'   
#' @details Note that the RTCA definition of well-clear is undergoing revision. 
#'   This code is based on the SLoWC formulation by Ethan Pratt and Jacob Kay as
#'   implemented in a MATLAB script by Ethan Pratt dated 2016-04-18.
#'   
#' @export
calculateSLoWC <- function(trajectory1, trajectory2) {
  if (!is.flighttrajectory(trajectory1) || !is.flighttrajectory(trajectory2)) {
    stop("Both arguments must be instances of flighttrajectory")
  }
  if (!isTRUE(all.equal(trajectory1$timestamp, trajectory2$timestamp))) {
    stop("Trajectories must have matching time stamps")
  }
  
  # Find the "origin" lon/lat for the encounter. Distances will be represented
  # in feet north/east from this point. Use the centroid of the trajectories.
  lon0 <- mean(c(trajectory1$longitude, trajectory2$longitude))
  lat0 <- mean(c(trajectory1$latitude, trajectory2$latitude))
  
  # Flat Earth approximation of aircraft position and velocity
  ac1XYZ <- cbind(lonlatToXY(trajectory1$longitude, trajectory1$latitude, 
                             lon0, lat0),
                  trajectory1$altitude)
  ac2XYZ <- cbind(lonlatToXY(trajectory2$longitude, trajectory2$latitude, 
                             lon0, lat0),
                  trajectory2$altitude)
  
  ac1Velocity <- bearingToXY(trajectory1$bearing, trajectory1$velocity)
  ac2Velocity <- bearingToXY(trajectory2$bearing, trajectory2$velocity)
  
  dXYZ <- ac2XYZ - ac1XYZ
  dXYZ[, 3] <- abs(dXYZ[, 3])
  relativeVelocity <- ac2Velocity - ac1Velocity
  
  # Calculate the range
  R <- sqrt(apply(dXYZ[, 1:2]^2, 1, sum))
  
  # Note: the code below here is very close to a direct translation of the 
  # MATLAB script to R (with a few modifications to permit parallelization). 
  # Additional optimizations are possible.
  
  # DAA Well Clear thresholds
  DMOD       <- 4000 # ft
  DH_thr     <- 450  # ft
  TauMod_thr <- 35   # s
  
  dX <- dXYZ[, 1]
  dY <- dXYZ[, 2]
  dH <- dXYZ[, 3]
  
  vrX <- relativeVelocity[, 1]
  vrY <- relativeVelocity[, 2]
  
  # Horizontal size of the Hazard Zone (TauMod_thr boundary)
  Rdot <- (dX * vrX + dY * vrY) / R;
  S <- pmax(DMOD, .5 * (sqrt( (Rdot * TauMod_thr)^2 + 4 * DMOD^2) - Rdot * TauMod_thr))
  # Safeguard against x/0
  S[R < 1e-4] <- DMOD
  
  # Calculate time to CPA and projected HMD
  tCPA <- -(dX * vrX + dY * vrY) / (vrX^2 + vrY^2)
  # Safegaurd against singularity
  tCPA[(vrX^2 + vrY^2) == 0 | (dX * vrX + dY * vrY) > 0] <- 0
  
  HMD <- sqrt( (dX + vrX * tCPA)^2 + (dY + vrY * tCPA)^2 )
  
  # Three penetration components (Range, HMD, vertical separation)
  RangePen <- pmin( ( R  / S)      , 1)
  HMDPen   <- pmin( (HMD / DMOD)   , 1)
  DHPen    <- pmin( (dH  / DH_thr) , 1)
  
  hpen <- FGnorm(RangePen, HMDPen)
  vSLoWC <- 100 * (1 - FGnorm(hpen, DHPen))
  
  return(vSLoWC)
}

#' Convert a bearing (in degrees) and velocity (in knots) to north and east
#' velocity (in ft / s).
bearingToXY <- function(bearing, velocity) {
  # Velocity should be in knots. Convert to ft / s
  fps <- velocity * 1.68781
  # Bearing should be degrees from north. Convert to radians.
  theta <- bearing * pi / 180
  # Return x and y components of the velocity in ft / s
  return(cbind(fps * sin(theta),
               fps * cos(theta)))
}

#' The Fernandez-Gausti squircular operator.
FGnorm <- function(x, y) {
  return(sqrt(x^2 + (1 - x^2) * y^2))
}