# Bit-width result artifacts

해석과 통합 비교는 [BITWIDTH_COMPARISON.md](../../BITWIDTH_COMPARISON.md)에 있음. 이 폴더는 원본 Project에서 가져온 software 검증 근거와 저장소에서 다시 실행한 검증 요약을 구분해 보존함.

| File / directory | 내용 |
| --- | --- |
| [accuracy_comparison.csv](accuracy_comparison.csv) | 원본의 float/Python fixed/RTL 성능, state별 RMSE, Q8.16 대비 변화율과 수치 진단 |
| [input_float_equivalence.json](input_float_equivalence.json) | 형식 간 입력/float 배열 동일성 |
| [latency_comparison.csv](latency_comparison.csv) | cycle CSV에서 계산한 latency/II와 출처 |
| [hardware_comparison.csv](hardware_comparison.csv) | 저장된 BKF L=1 Vivado report 세 형식 비교 |
| [q8_14/](q8_14/), [q8_12/](q8_12/) | 원본 Project의 format/implementation/test status, 로그, 단위·독립 산술 검사, cycle CSV와 plot |
| [q8_16/](q8_16/) | 원본의 fresh baseline 비교 snapshot에서 가져온 format, implementation status와 cycle CSV |
| [q8_16_generalization_summary.json](q8_16_generalization_summary.json) | 원본 W24/F16 재현의 compact projection; 원본 SHA256과 비교 범위 포함 |
| [package_validation.json](package_validation.json) | 2026-09-14 저장소 이식 후 실행한 검증 요약; 원본 snapshot과 분리 |
| [source_manifest.json](source_manifest.json) | 가져온 파일의 원본→저장소 경로, SHA256, 익명화·요약 변환 |

`q8_14/`와 `q8_12/`에서 `implementation.json`은 1-step/500-step을 각각 기록하고 `rtl_comparison.json`은 500-step 비교를 기록함. `runs/<algorithm>_<steps>/comparison.json`과 cycle CSV는 각 실행을 구분함. `test_status.json`의 명령과 로그 문자열은 원본 Project 실행 당시 기록이며, 공개용 로그는 Git의 생성물 `*.log` 제외 규칙을 유지하기 위해 `.txt`로 보존함. Local 상대 경로와 확장자 변경은 `source_manifest.json`의 매핑을 통해 찾을 수 있음. 재실행된 variant-local 결과를 이 과거 기록으로 대체하지 않음.

`accuracy_comparison.csv`의 `hardware_status=NOT_RUN`은 당시 software 실험이 Vivado를 실행하지 않았음을 뜻함. 2026-09-11의 별도 hardware 결과는 [q8_14](../vivado/q8_14/)와 [q8_12](../vivado/q8_12/)에 있으며 BKF L=1만 포함함. 이번 저장소 업데이트에서 Vivado를 다시 실행하지 않았음.

선택 plot은 각 형식의 `plots/error_norm.png`와 `plots/float_fixed_rtl_comparison.png`임. 원본의 binary reference, RTL output 전체, 중복 peer/baseline source tree, compile 산출물, Vivado DCP는 제외함. 해당 형식의 `make bitwidth`와 별도 Q8.16 재현 target으로 새 결과를 생성할 수 있음.
