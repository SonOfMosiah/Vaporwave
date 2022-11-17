export function toChainlinkPrice(value: any) {
  return (value * Math.pow(10, 8)).toString();
}
